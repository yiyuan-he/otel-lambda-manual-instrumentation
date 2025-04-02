require 'bundler/setup'
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/aws_sdk'
require 'opentelemetry/instrumentation/aws_lambda'
require 'aws-sdk-s3'

# Configure OpenTelemetry
OpenTelemetry::SDK.configure do |c|
  # Use your Lambda propagator

  # Configure exporters, etc.
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
      OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
    )
  )

  # Install instrumentations
  c.use 'OpenTelemetry::Instrumentation::AwsLambda'
  c.use 'OpenTelemetry::Instrumentation::AwsSdk'
end

# Lambda handler
def lambda_handler(event:, context:)
  # Debug logging
  puts "Lambda environment: #{ENV['_X_AMZN_TRACE_ID']}"
  current_span = OpenTelemetry::Trace.current_span
  puts "Current trace ID: #{current_span.context.hex_trace_id}" if current_span.context.valid?

  # Code
  tracer = OpenTelemetry.tracer_provider.tracer('manual.tracer')
  tracer.in_span('manual_root_span', kind: :server) do |root_span|
    s3_client = Aws::S3::Client.new
    s3_client.list_buckets
  end
end
