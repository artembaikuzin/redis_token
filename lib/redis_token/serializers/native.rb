class RedisToken
  class Serializers
    class Native
      def pack(value)
        Marshal.dump(value)
      end

      def unpack(value)
        Marshal.load(value)
      end
    end
  end
end
