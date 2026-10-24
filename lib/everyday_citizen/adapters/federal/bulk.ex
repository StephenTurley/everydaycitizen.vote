defmodule EverydayCitizen.Adapters.Federal.Bulk do
  @moduledoc """
  GovInfo bulk data zips. A zip is downloaded to a temp file and its XML entries
  are read one at a time, so memory holds the download and one entry, never the
  whole extract. Each entry gets its own `SourceRef`: the per-file bulkdata URL
  (the zip's directory plus the entry name), the download time, and the hash of
  the entry's bytes, which are the bytes that URL serves.
  """
  alias EverydayCitizen.Adapters.Federal.HTTP
  alias EverydayCitizen.Ingest.Records.SourceRef

  defmodule Zip do
    @moduledoc false
    @enforce_keys [:path, :handle, :base_url, :fetched_at]
    defstruct [:path, :handle, :base_url, :fetched_at]
  end

  @doc """
  Downloads `url`, calls `fun.(zip)` and returns `{:ok, result}`. The temp file
  is deleted afterwards, even when `fun` raises.
  """
  @spec with_zip(String.t(), (Zip.t() -> term())) :: {:ok, term()} | {:error, term()}
  def with_zip(url, fun) do
    with {:ok, %{raw: raw, source: source}} <- HTTP.get(url, limiter: :govinfo, decode: :raw),
         :ok <- ensure_not_html(raw) do
      path =
        Path.join(
          System.tmp_dir!(),
          "everyday_citizen-bulk-#{System.unique_integer([:positive])}.zip"
        )

      try do
        File.write!(path, raw)

        case :zip.zip_open(String.to_charlist(path), [:memory]) do
          {:ok, handle} ->
            zip = %Zip{
              path: path,
              handle: handle,
              base_url: url |> Path.dirname() |> Kernel.<>("/"),
              fetched_at: source.fetched_at
            }

            try do
              {:ok, fun.(zip)}
            after
              :zip.zip_close(handle)
            end

          {:error, _} ->
            {:error, :not_a_zip}
        end
      after
        File.rm(path)
      end
    end
  end

  # GovInfo answers a missing file with HTTP 200 and an HTML page.
  defp ensure_not_html(raw), do: if(HTTP.html?(raw), do: {:error, :not_a_zip}, else: :ok)

  @doc "Number of `.xml` entries in the zip."
  @spec count_entries(Zip.t()) :: non_neg_integer()
  def count_entries(%Zip{} = zip), do: zip |> xml_names() |> length()

  @doc """
  Folds `fun.({name, bytes, source}, acc)` over the zip's `.xml` entries, in
  archive order, reading one entry into memory at a time. An entry that cannot be
  read is passed as `{name, {:error, reason}, nil}`. With `range: {offset, limit}`
  only that slice of the entries is read, so a large zip can be split across jobs.
  """
  @spec reduce_entries(
          Zip.t(),
          acc,
          ({String.t(), binary() | {:error, term()}, SourceRef.t() | nil}, acc -> acc),
          keyword()
        ) :: acc
        when acc: term()
  def reduce_entries(%Zip{handle: handle} = zip, acc, fun, opts \\ []) do
    names =
      case opts[:range] do
        nil -> xml_names(zip)
        {offset, limit} -> zip |> xml_names() |> Enum.slice(offset, limit)
      end

    Enum.reduce(names, acc, fn name, acc ->
      case :zip.zip_get(String.to_charlist(name), handle) do
        {:ok, {_, bytes}} ->
          source = SourceRef.new(zip.base_url <> Path.basename(name), bytes, zip.fetched_at)
          fun.({Path.basename(name), bytes, source}, acc)

        {:error, reason} ->
          fun.({Path.basename(name), {:error, reason}, nil}, acc)
      end
    end)
  end

  defp xml_names(%Zip{handle: handle}) do
    {:ok, listing} = :zip.zip_list_dir(handle)

    for {:zip_file, name, _info, _comment, _offset, _size} <- listing,
        name = List.to_string(name),
        String.ends_with?(name, ".xml"),
        do: name
  end
end
