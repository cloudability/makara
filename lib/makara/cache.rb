require 'active_support/core_ext/object/try'

# The Makara Cache should have access to your centralized cache store.
# It serves the purpose of storing the Makara::Context across requests, servers, etc.

module Makara
  module Cache

    autoload :MemoryStore, 'makara/cache/memory_store'
    autoload :NoopStore,   'makara/cache/noop_store'

    class << self

      def store=(store)
        @store = store
      end

      def read(key)
        store.try(:read, key)
      end

      def write(key, value, ttl)
        store.try(:write, key, value, :expires_in => ttl.to_i)
      end

      protected

      def store
        case @store
        when :noop, :null
          @store = Makara::Cache::NoopStore.new
        when :memory
          @store = Makara::Cache::MemoryStore.new
        else
          @store ||= Rails.cache if defined?(Rails)
        end

        @store
      end

    end

  end
end
