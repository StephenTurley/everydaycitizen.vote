defmodule TheFloor.Adapters.Federal.ActionClassifierTest do
  use ExUnit.Case, async: true

  alias TheFloor.Adapters.Federal.ActionClassifier

  @table [
    {"Introduced in House", "introduced"},
    {"Read twice and referred to the Committee on Finance.", "referred"},
    {"Referred to the House Committee on Ways and Means.", "referred"},
    {"Subcommittee Hearings Held", "hearing"},
    {"Committee Consideration and Mark-up Session Held", "markup"},
    {"Ordered to be Reported (Amended) by Voice Vote.", "markup"},
    {"Reported (Amended) by the Committee on Energy and Commerce. H. Rept. 119-12.", "reported"},
    {"Placed on the Union Calendar, Calendar No. 12.", "scheduled"},
    {"Passed/agreed to in House: On passage Passed by recorded vote: 220 - 207 (Roll no. 45).",
     "passed_chamber"},
    {"Passed Senate without amendment by Unanimous Consent.", "passed_chamber"},
    {"Amendment SA 12 agreed to in Senate by Voice Vote.", "amended"},
    {"Conference report H. Rept. 119-50 filed.", "conference"},
    {"Presented to President.", "enrolled"},
    {"Signed by President.", "signed"},
    {"Vetoed by President.", "vetoed"},
    {"Became Public Law No: 119-4.", "became_law"},
    {"Motion to reconsider laid on the table Agreed to without objection.", nil},
    {"Motion to proceed to consideration of measure agreed to in Senate by Yea-Nay Vote. 77 - 22. Record Vote Number: 233.",
     nil},
    {"Cloture on the motion to proceed to the measure invoked in Senate by Yea-Nay Vote. 74 - 24.",
     nil},
    {"Passed Senate with an amendment by Yea-Nay Vote. 77 - 22. Record Vote Number: 250.",
     "passed_chamber"}
  ]

  describe "classify/1" do
    for {text, expected} <- @table do
      test "#{inspect(text)} -> #{inspect(expected)}" do
        assert ActionClassifier.classify(%{"text" => unquote(text), "type" => nil}) ==
                 unquote(expected)
      end
    end

    test "matches case-insensitively" do
      assert ActionClassifier.classify(%{"text" => "INTRODUCED IN HOUSE", "type" => nil}) ==
               "introduced"
    end

    test "ignores the raw type and classifies on text" do
      assert ActionClassifier.classify(%{"text" => "Signed by President.", "type" => "Floor"}) ==
               "signed"
    end
  end
end
