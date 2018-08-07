module Graphiti
  class Resource
    module Sideloading
      def self.included(klass)
        klass.extend ClassMethods
      end

      module ClassMethods
        def allow_sideload(name, opts = {}, &blk)
          klass = Class.new(opts.delete(:class) || Sideload)
          klass.class_eval(&blk) if blk
          opts[:parent_resource] = self
          relationship_option(opts, :readable)
          relationship_option(opts, :writable)
          sideload = klass.new(name, opts)
          if parent = opts[:parent]
            parent.children[name] = sideload
          else
            config[:sideloads][name] = sideload
            apply_sideloads_to_serializer
          end
          sideload
        end

        def apply_sideloads_to_serializer
          Util::SerializerRelationships.new(self, config[:sideloads]).apply
        end

        def has_many(name, opts = {}, &blk)
          opts[:class] = adapter.sideloading_classes[:has_many]
          allow_sideload(name, opts, &blk)
        end

        def belongs_to(name, opts = {}, &blk)
          opts[:class] = adapter.sideloading_classes[:belongs_to]
          allow_sideload(name, opts, &blk)
        end

        def has_one(name, opts = {}, &blk)
          opts[:class] = adapter.sideloading_classes[:has_one]
          allow_sideload(name, opts, &blk)
        end

        def many_to_many(name, opts = {}, &blk)
          opts[:class] = adapter.sideloading_classes[:many_to_many]
          allow_sideload(name, opts, &blk)
        end

        def polymorphic_belongs_to(name, opts = {}, &blk)
          opts[:resource] ||= Class.new(::Graphiti::Resource) do
            self.polymorphic = []
            self.abstract_class = true
          end
          # adapters *probably* don't need to override this, but it's allowed
          opts[:class] ||= adapter.sideloading_classes[:polymorphic_belongs_to]
          opts[:class] ||= ::Graphiti::Sideload::PolymorphicBelongsTo
          allow_sideload(name, opts, &blk)
        end

        def belongs_to_many(name, resource: nil, as:, &blk)
          resource = resource ||= Util::Class.infer_resource_class(self, name)
          sideload = resource.sideload(as)

          _adapter = adapter
          filter sideload.true_foreign_key, resource.attributes[:id][:type] do
            eq do |scope, value|
              _adapter.belongs_to_many_filter(sideload, scope, value)
            end
          end
        end

        def sideload(name)
          sideloads[name]
        end

        def all_sideloads(memo = {})
          sideloads.each_pair do |name, sideload|
            unless memo[name]
              memo[name] = sideload
              memo.merge!(sideload.resource.class.all_sideloads(memo))
            end
          end
          memo
        end

        def association_names(memo = [])
          all_sideloads.each_pair do |name, sl|
            unless memo.include?(sl.name)
              memo << sl.name
              memo |= sl.resource.class.association_names(memo)
            end
          end

          memo
        end

        def association_types(memo = [])
          all_sideloads.each_pair do |name, sl|
            unless memo.include?(sl.resource.type)
              memo << sl.resource.type
              memo |= sl.resource.class.association_types(memo)
            end
          end

          memo
        end
      end
    end
  end
end