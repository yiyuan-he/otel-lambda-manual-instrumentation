require 'json'
require 'opentelemetry/sdk'

# Configure OpenTelemetry before Lambda handler
OpenTelemetry::SDK.configure do |c|
  c.service_name = 'my-lambda-service'
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(
      OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
    )
  )
end

def lambda_handler(event:, context:)
  # Get a tracer
  tracer = OpenTelemetry.tracer_provider.tracer('lambda-tracer')
  
  # Create a single span for the entire Lambda execution
  tracer.in_span('lambda_execution') do |span|
    # Add basic information to the span
    span.set_attribute('request_id', context.aws_request_id)
    
    # Your Lambda business logic here
    result = "Hello from Lambda!"
    
    # Add result information to the span
    span.add_event('Completed processing')
    
    # Ensure telemetry is flushed before Lambda finishes
    OpenTelemetry.tracer_provider.force_flush
    
    # Return response
    { 
      statusCode: 200, 
      body: JSON.generate({ message: result })
    }
  end
end
