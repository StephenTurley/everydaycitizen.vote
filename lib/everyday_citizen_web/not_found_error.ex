defmodule EverydayCitizenWeb.NotFoundError do
  @moduledoc "Raised for a page whose record does not exist; renders the 404 page."
  defexception message: "not found", plug_status: 404
end
