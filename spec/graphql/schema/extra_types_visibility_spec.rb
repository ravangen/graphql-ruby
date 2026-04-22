# frozen_string_literal: true

require "spec_helper"

describe "extra_types with visibility profiles" do
  module ExtraTypesVisibilityTest
    module HiddenInterface
      include GraphQL::Schema::Interface

      description "An interface that should only be visible in the internal profile."

      definition_methods do
        def visible?(ctx)
          ctx[:internal] == true
        end
      end

      field :name, String, null: false
    end

    class ConcreteImpl < GraphQL::Schema::Object
      description "A concrete type implementing the hidden interface."
      implements HiddenInterface
      field :name, String, null: false
    end

    HiddenInterface.orphan_types(ConcreteImpl)

    class Query < GraphQL::Schema::Object
      field :greeting, String, fallback_value: "hello"
    end

    class Schema < GraphQL::Schema
      query(Query)
      extra_types(HiddenInterface)
      use GraphQL::Schema::Visibility, profiles: {
        public: {},
        internal: { internal: true },
      }
    end
  end

  def type_names_for(profile)
    ExtraTypesVisibilityTest::Schema.execute(
      "{ __schema { types { name } } }",
      context: { visibility_profile: profile },
    )["data"]["__schema"]["types"].map { |t| t["name"] }
  end

  it "includes the interface and its concrete type in the internal profile" do
    types = type_names_for(:internal)
    assert_includes types, "HiddenInterface"
    assert_includes types, "ConcreteImpl"
  end

  it "excludes the interface and its concrete type from the public profile" do
    types = type_names_for(:public)
    refute_includes types, "HiddenInterface",
      "extra_types should respect visible? — HiddenInterface should not appear in the public profile"
    refute_includes types, "ConcreteImpl",
      "extra_types should respect visible? — ConcreteImpl should not appear in the public profile"
  end
end
