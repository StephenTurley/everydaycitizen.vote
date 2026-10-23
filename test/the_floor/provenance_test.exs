defmodule TheFloor.ProvenanceTest do
  use TheFloor.DataCase, async: true

  alias TheFloor.Ingest.Records.SourceRef
  alias TheFloor.Provenance
  alias TheFloor.Provenance.Source
  alias TheFloor.Repo

  describe "SourceRef.new/3" do
    test "hashes the body" do
      assert SourceRef.new("u", "abc").content_hash ==
               "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    end
  end

  describe "upsert_source/2" do
    test "is idempotent" do
      early = ~U[2026-01-01 00:00:00.000000Z]
      ref = SourceRef.new("https://example.test/a", "body", early)

      {:ok, first} = Provenance.upsert_source(ref, nil)
      {:ok, second} = Provenance.upsert_source(ref, nil)

      assert first.id == second.id
      assert Repo.aggregate(Source, :count) == 1
      assert DateTime.compare(second.last_seen_at, first.last_seen_at) == :gt
      assert second.fetched_at == early
      assert Repo.get!(Source, first.id).fetched_at == early
    end

    test "same url, new body creates a new source row" do
      {:ok, a} = Provenance.upsert_source(SourceRef.new("https://example.test/a", "one"), nil)
      {:ok, b} = Provenance.upsert_source(SourceRef.new("https://example.test/a", "two"), nil)

      refute a.id == b.id
      assert Repo.aggregate(Source, :count) == 2
    end

    test "records the ingest run" do
      {:ok, run} = Provenance.start_run("adapter", "job")
      {:ok, source} = Provenance.upsert_source(SourceRef.new("u", "x"), run.id)
      assert source.ingest_run_id == run.id
    end
  end

  describe "last_succeeded_run/2" do
    test "ignores failed and running runs" do
      assert Provenance.last_succeeded_run("a", "j") == nil

      {:ok, ok} = Provenance.start_run("a", "j")
      {:ok, ok} = Provenance.finish_run(ok, :succeeded, %{"n" => 1}, nil)
      {:ok, failed} = Provenance.start_run("a", "j")
      {:ok, _} = Provenance.finish_run(failed, :failed, %{}, "boom")
      {:ok, _running} = Provenance.start_run("a", "j")
      {:ok, other} = Provenance.start_run("a", "other")
      {:ok, _} = Provenance.finish_run(other, :succeeded, %{}, nil)

      assert Provenance.last_succeeded_run("a", "j").id == ok.id
      assert ok.stats == %{"n" => 1}
    end
  end
end
