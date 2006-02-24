class CGI #:nodoc:
  module QueryExtension
    private
    def setup_raw_put_data
      stdinput.binmode if stdinput.respond_to?(:binmode)
      content = stdinput.read(Integer(env_table['CONTENT_LENGTH'])) || ''
      env_table['RAW_POST_DATA'] = content.freeze
    end

    def read_query_params(method)
      case method
      when :get
        read_params_from_query
      when :post
        read_params_from_post
      when :put
        setup_raw_put_data
        read_params_from_query
      when :cmd
        read_from_cmdline
      else # when :head, :delete, :options
        read_params_from_query
      end
    end
  end
end
