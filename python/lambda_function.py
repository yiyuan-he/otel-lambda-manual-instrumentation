import os
import json
import boto3

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor, ConsoleSpanExporter
from opentelemetry.sdk.resources import Resource

resource = Resource.create({
    "service.name": "validation-lambda",
    "service.namespace": "aws-lambda",
    "cloud.provider": "aws"
})

# Set up tracer provider with resource information
tracer_provider = TracerProvider(resource=resource)
trace.set_tracer_provider(tracer_provider)

# Use console exporter for now -- will be replaced with UDP exporter later
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
        lambda_span.set_attribute("service.name", "validation-lambda")

        # Add AWS Lambda context information to the span
        if context:
            lambda_span.set_attribute("aws.lambda.function_name", context.function_name)
            lambda_span.set_attribute("aws.lambda.function_version", context.function_version)
            lambda_span.set_attribute("aws.lambda.invocation_id", context.aws_request_id)
            lambda_span.set_attribute("aws.lambda.memory_limit_in_mb", int(context.memory_limit_in_mb))

        # Add event information if available
        if event:
            if isinstance(event, dict):
                if 'httpMethod' in event:
                    lambda_span.set_attribute("http.method", event['httpMethod'])
                if 'path' in event:
                    lambda_span.set_attribute("http.path", event['path'])

        with tracer.start_as_current_span("business_logic") as business_span:
            business_span.set_attribute("test.attribute", "test_value")
            business_span.add_event("processing_started", {"timestamp": context.get_remaining_time_in_millis()})

            trace_id = format(business_span.get_span_context().trace_id, "032x")

            business_span.add_event("business_logic_event", {"event.data": "Processing business logic"})

            with tracer.start_as_current_span("s3_operation") as s3_span:
                s3_span.set_attribute("aws.service", "s3")
                s3_span.set_attribute("aws.operation", "list_buckets")

                try:
                    s3_client = boto3.client("s3")
                    response = s3_client.list_buckets()

                    bucket_count = len(response["Buckets"])
                    s3_span.set_attribute("aws.s3.bucket_count", bucket_count)
                    s3_span.set_status(trace.StatusCode.OK)
                    print(f"Found {bucket_count} buckets")
                except Exception as e:
                    s3_span.set_status(trace.StatusCode.ERROR, str(e))
                    s3_span.record_exception(e)
                    print(f"Error listing buckets: {e}")

            # Add completion event
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
