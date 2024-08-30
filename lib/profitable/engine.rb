module Profitable
  class Engine < ::Rails::Engine
    isolate_namespace Profitable

    # TODO: implement config
    # initializer "Profitable.load_configuration" do
    #   config_file = Rails.root.join("config", "profitable.rb")
    #   if File.exist?(config_file)
    #     Profitable.configure do |config|
    #       config.instance_eval(File.read(config_file))
    #     end
    #   end
    # end
  end
end
