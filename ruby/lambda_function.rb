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

  # Configure span processor with console exporter
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
      OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
    )
  )

  # Install instrumentations (but we'll handle context manually)
  c.use 'OpenTelemetry::Instrumentation::AwsSdk'
end

puts "OpenTelemetry configuration complete"

# Lambda handler
def lambda_handler(event:, context:)
  # Get the X-Ray header (which is now available during handler execution)
  xray_header = ENV['_X_AMZN_TRACE_ID']
  puts "Lambda handler - X-Ray header: #{xray_header}"

  # Manually extract context from X-Ray header if it exists
  context_token = nil

  if xray_header && defined?(OpenTelemetry::Propagator::XRay)
    puts "Extracting context from X-Ray header"

    # Create empty context and carrier
    empty_context = OpenTelemetry::Context.empty
    empty_carrier = {}

    # Get the propagator
    propagator = OpenTelemetry::Propagator::XRay.lambda_text_map_propagator

    # Extract context from carrier (the propagator should check ENV)
    extracted_context = propagator.extract(empty_carrier, context: empty_context)

    # Check if extraction was successful
    extracted_span = OpenTelemetry::Trace.current_span(extracted_context)
    if extracted_span.context.valid?
      puts "Successfully extracted context with trace ID: #{extracted_span.context.hex_trace_id}"

      # Parse X-Ray header to verify
      parts = xray_header.split(';')
      root_part = parts.find { |p| p.start_with?('Root=') }

      if root_part
        root_value = root_part.split('=', 2)[1]
        if root_value.start_with?('1-')
          # Remove the "1-" prefix and any hyphens
          trace_id_without_version = root_value[2..].gsub('-', '')
          puts "X-Ray trace ID: #{root_value}"
          puts "Extracted trace ID: #{extracted_span.context.hex_trace_id}"
          puts "Do they match? #{extracted_span.context.hex_trace_id == trace_id_without_version}"
        end      
      end

      # Set the extracted context as current
      context_token = OpenTelemetry::Context.attach(extracted_context)
    else
      puts "Failed to extract valid context from X-Ray header"
    end
  end

  # Get a tracer
  tracer = OpenTelemetry.tracer_provider.tracer('lambda_handler', '1.0')

  # Create a simple child span
  tracer.in_span('lambda_operation', kind: OpenTelemetry::Trace::SpanKind::INTERNAL) do |span|
    # Log span information to verify parent-child relationship
    puts "Created span with trace ID: #{span.context.hex_trace_id}"
    puts "Span ID: #{span.context.hex_span_id}"

    # Do a simple operation
    s3_client = Aws::S3::Client.new
    result = s3_client.list_buckets

    # Add a simple attribute
    span.set_attribute('bucket.count', result.buckets.count)
  end

  # Force flush spans before returning
  OpenTelemetry.tracer_provider.force_flush

  # Return response
  { statusCode: 200, body: "Lambda trace completed" }
ensure
  # Detach the context if we set one
  OpenTelemetry::Context.detach(context_token) if context_token
end
