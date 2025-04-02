# Debug information about the environment
puts "LAMBDA STARTUP: Initializing..."
puts "Ruby version: #{RUBY_VERSION}"
puts "PWD: #{Dir.pwd}"

# Set up gem paths
gem_path = File.join(Dir.pwd, 'vendor/bundle/ruby/3.2.0')
ENV['GEM_PATH'] = gem_path
ENV['GEM_HOME'] = gem_path

# Require bundler and load all gems
require 'rubygems'
require 'bundler/setup'

# Try to require the opentelemetry-propagator-xray gem
begin
  require 'opentelemetry-propagator-xray'
  puts "Successfully loaded X-Ray propagator through standard require"
rescue LoadError
  begin
    require File.join(gem_path, 'gems/opentelemetry-propagator-xray-0.23.0/lib/opentelemetry-propagator-xray')
    puts "Successfully loaded X-Ray propagator through direct path"
  rescue LoadError => e
    puts "Failed to load X-Ray propagator: #{e.message}"
  end
end

# Try to require the UDP exporter gem using the full file path
udp_gem_file = File.join(gem_path, 'gems/aws-opentelemetry-exporter-otlp-udp-0.0.1/lib/aws-opentelemetry-exporter-otlp-udp.rb')
begin
  puts "Attempting to load UDP exporter from absolute path: #{udp_gem_file}"
  require udp_gem_file
  puts "Successfully loaded AWS OpenTelemetry UDP exporter from absolute path"
  udp_exporter_loaded = true
rescue LoadError => e
  puts "Failed to load AWS OpenTelemetry UDP exporter from absolute path: #{e.message}"
  udp_exporter_loaded = false
end

# If the above didn't work, try an alternative approach with relative path
if !udp_exporter_loaded
  begin
    # Add the lib directory to the load path
    $LOAD_PATH.unshift(File.join(gem_path, 'gems/aws-opentelemetry-exporter-otlp-udp-0.0.1/lib'))
    require 'aws-opentelemetry-exporter-otlp-udp'
    puts "Successfully loaded AWS OpenTelemetry UDP exporter via $LOAD_PATH"
    udp_exporter_loaded = true
  rescue LoadError => e
    puts "Failed to load AWS OpenTelemetry UDP exporter via $LOAD_PATH: #{e.message}"
  end
end

# Load other required gems
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/aws_sdk'
require 'opentelemetry/instrumentation/aws_lambda'
require 'aws-sdk-s3'

# Configure OpenTelemetry
OpenTelemetry::SDK.configure do |c|
  # Try to use X-Ray propagator if available
  if defined?(OpenTelemetry::Propagator::XRay)
    puts "Using X-Ray Lambda propagator"
    c.propagators = [OpenTelemetry::Propagator::XRay.lambda_text_map_propagator]
  else
    # Use W3C TraceContext propagator
    puts "Using W3C TraceContext propagator"
    c.propagators = [OpenTelemetry::Trace::Propagation::TraceContext.text_map_propagator]
  end

  # Set a service name
  c.resource = OpenTelemetry::SDK::Resources::Resource.create({
    'service.name' => 'ruby-lambda-otel',
    'deployment.environment' => 'production'
  })

  # Add UDP exporter if available
  if defined?(AWS::OpenTelemetry::Exporter::OTLP::UDP::OTLPUdpSpanExporter)
    puts "Adding UDP exporter for telemetry data"
    udp_trace_exporter = AWS::OpenTelemetry::Exporter::OTLP::UDP::OTLPUdpSpanExporter.new

    # Add a batch span processor with the UDP exporter
    c.add_span_processor(
      OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
        udp_trace_exporter
      )
    )
    puts "UDP exporter configured successfully"
  else
    puts "UDP exporter class not available"
  end

  # Install instrumentations (but we'll handle context manually)
  c.use 'OpenTelemetry::Instrumentation::AwsSdk'
  c.use 'OpenTelemetry::Instrumentation::AwsLambda'
end

puts "OpenTelemetry configuration complete"

# Create Lambda handler module with instrumentation
module Example
  class Handler
    extend OpenTelemetry::Instrumentation::AwsLambda::Wrap

    def self.process(event:, context:)
      # Get the X-Ray header for debugging
      xray_header = ENV['_X_AMZN_TRACE_ID']
      puts "Lambda handler - X-Ray header: #{xray_header}"

      # Log current span details
      current_span = OpenTelemetry::Trace.current_span
      puts "Current span ID: #{current_span.context.hex_span_id}"
      puts "Current span trace ID: #{current_span.context.hex_trace_id}"

      s3_client = Aws::S3::Client.new
      s3_result = s3_client.list_buckets

      # Return response
      { statusCode: 200, body: "Lambda trace completed" }
    end

    # Instrument the handler method
    instrument_handler :process
  end
end

# Export the handler function for AWS Lambda
def lambda_handler(event:, context:)
  Example::Handler.process(event: event, context: context)
end
