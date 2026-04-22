# frozen_string_literal: true

require "spec_helper"

describe "extra_types with visibility profiles" do
  # Reproduces a pattern from Shopify's Admin GraphQL schema:
  #
  # - A `Query.reference` field returns the `Node` interface
  # - A `NavigationResource` interface (visibility-gated) implements `Node`
  #   and has concrete types (`AdminLink`) registered via `orphan_types`
  # - At runtime, `reference` can resolve to an `AdminLink` through
  #   `NavigationResource.resolve_type`
  # - `NavigationResource` is not referenced by any field directly, so
  #   the schema only discovers it and its concrete types via `extra_types`
  #
  # The bug: `extra_types` bypasses visibility checks, so
  # `NavigationResource` and `AdminLink` leak into profiles where
  # `visible?` returns false.

  module ExtraTypesVisibilityTest
    module Node
      include GraphQL::Schema::Interface
      field :id, GraphQL::Types::ID, null: false
    end

    # A visibility-gated interface that implements Node.
    # Only visible in the internal profile.
    module NavigationResource
      include GraphQL::Schema::Interface
      implements Node

      definition_methods do
        def visible?(ctx)
          ctx[:internal] == true
        end

        def resolve_type(_obj, _ctx)
          AdminLink
        end
      end

      field :id, GraphQL::Types::ID, null: false
      field :url, String, null: false
    end

    class AdminLink < GraphQL::Schema::Object
      implements NavigationResource
      field :id, GraphQL::Types::ID, null: false
      field :url, String, null: false
    end

    NavigationResource.orphan_types(AdminLink)

    class Query < GraphQL::Schema::Object
      # Returns the Node interface — like SearchResult.reference in Shopify
      field :reference, Node, null: true
    end

    class Schema < GraphQL::Schema
      query(Query)

      # NavigationResource is not reachable through field traversal
      # (no field returns it), so extra_types is the only way to
      # register it and its concrete types in the schema.
      extra_types(NavigationResource)

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

  it "includes NavigationResource and AdminLink in the internal profile" do
    types = type_names_for(:internal)
    assert_includes types, "NavigationResource"
    assert_includes types, "AdminLink"
  end

  it "excludes NavigationResource and AdminLink from the public profile" do
    types = type_names_for(:public)
    refute_includes types, "NavigationResource",
      "extra_types should respect visible? — NavigationResource should not appear in the public profile"
    refute_includes types, "AdminLink",
      "extra_types should respect visible? — AdminLink should not appear in the public profile"
  end
end
