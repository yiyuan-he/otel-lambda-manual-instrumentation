import json

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor, ConsoleSpanExporter

tracer_provider = TracerProvider()
trace.set_tracer_provider(tracer_provider)

# Use console exporter for now -- will be replace with UDP exporter later
console_exporter = ConsoleSpanExporter()
tracer_provider.add_span_processor(SimpleSpanProcessor(console_exporter))

# Get tracer
tracer = trace.get_tracer(__name__)

# lambda function
def lambda_handler(event, context):
    """
    AWS Lambda handler with basic OpenTelemetry instrumentation.

    Parameters:
    event (dict): The event data passed to the Lambda function
    context (LambdaContext): Lambda runtime information

    Returns:
    dict: Response containing the trace ID
    """
    # Create a span for the entire lambda handler
    with tracer.start_as_current_span("lambda_handler") as lambda_span:
        lambda_span.set_attribute("service.name", "python-otel-lambda")

        with tracer.start_as_current_span("business_logic") as business_span:
            business_span.set_attribute("test.attribute", "test_value")
            business_span.add_event("processing_started", {"timestamp": context.get_remaining_time_in_millis()})

            trace_id = format(business_span.get_span_context().trace_id, "032x")

        business_span.add_event("processing_completed", {"timestamp": context.get_remaining_time_in_millis()})

    success = tracer_provider.force_flush()
    print(f"Force flush {'succeeded' if success else 'failed'}")

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Trace created successfully",
            "traceId": trace_id
        })
    }
