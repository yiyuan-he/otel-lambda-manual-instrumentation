require 'bundler/setup'
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/aws_sdk'
require 'opentelemetry/instrumentation/aws_lambda'
require 'opentelemetry/propagator/xray'

# Configure OpenTelemetry
OpenTelemetry::SDK.configure do |c|
  # Use your Lambda propagator
  c.propagators = [OpenTelemetry::Propagator::XRay.lambda_text_map_propagator]
  
  # Configure exporters, etc.
  # ...
  
  # Install instrumentations
  c.use 'OpenTelemetry::Instrumentation::AwsLambda'
  c.use 'OpenTelemetry::Instrumentation::Aws::Sdk'
end

# Lambda handler
def lambda_handler(event:, context:)
  # Debug logging
  puts "Lambda environment: #{ENV['_X_AMZN_TRACE_ID']}"
  current_span = OpenTelemetry::Trace.current_span
  puts "Current trace ID: #{current_span.context.hex_trace_id}" if current_span.context.valid?

  # Code
  puts "Hello from Lambda!"
end
