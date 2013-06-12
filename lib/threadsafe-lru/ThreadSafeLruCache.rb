require 'thread'
require 'threadsafe-lru/DoubleLinkedList'

module ThreadSafeLru
  class LruCache
    def initialize size, opts = {}, &block
      @opts=opts
      @size=size
      @cached_values={}
      @factory_block=block
      @recently_used=ThreadSafeLru::DoubleLinkedList.new
      @lock=Mutex.new
    end

    def size
      @cached_values.size
    end

    
    def drop key
      @lock.synchronize do
        node=@cached_values.delete key
        node.remove if node
          
      end
    end
      
    
    def clear
      @lock.synchronize do
        @cached_values.clear
        @recently_used.clear
      end
    end
    
    def get key, &block
      node=nil
      @lock.synchronize do
        node=get_node(key)
      end
      node.get_value(block ? block : @factory_block)
    end

    private

    def get_node key
      if @cached_values.has_key?(key)
        dll_node=@cached_values[key]
        @recently_used.bump_to_top dll_node
      else
        while (size >= @size) do
          dropped=@recently_used.remove_last
          @cached_values.delete(dropped.value.key)

          if @opts[:on_eviction]
            @opts[:on_eviction].call(dropped.value.key, dropped.value.get_value)
          end
        end
        node=Node.new key
        dll_node=@recently_used.add_to_head node
        @cached_values[key]=dll_node        
      end
      @cached_values[key].value
    end

  end

  class Node
    def initialize key
      @key=key
      @produced=false
      @value=nil
      @lock=Mutex.new
    end

    attr_reader :key

    def get_value block = nil
      @lock.synchronize do
        if !@produced && block
          @value=block.call @key
          @produced=true
        end
        @value
      end
    end
  end

end
