FROM public.ecr.aws/lambda/ruby:3.2

# Install development tools needed for native extensions
RUN yum install -y gcc make git

# Set up the working directory
WORKDIR ${LAMBDA_TASK_ROOT}

# Copy dependency files
COPY Gemfile Gemfile.lock* ${LAMBDA_TASK_ROOT}/

# Install all gems from Gemfile first
RUN bundle config set --local path 'vendor/bundle' && \
    bundle install

# Copy the local gem
COPY opentelemetry-propagator-xray-0.23.0.gem ${LAMBDA_TASK_ROOT}/
COPY aws-opentelemetry-exporter-otlp-udp-0.0.1.gem ${LAMBDA_TASK_ROOT}/

# Now install the local gem into the SAME gem directory that bundle used
RUN GEM_HOME=${LAMBDA_TASK_ROOT}/vendor/bundle/ruby/3.2.0 \
    gem install --local opentelemetry-propagator-xray-0.23.0.gem && \
    GEM_HOME=${LAMBDA_TASK_ROOT}/vendor/bundle/ruby/3.2.0 \
    gem install --local aws-opentelemetry-exporter-otlp-udp-0.0.1.gem

# Copy function code
COPY lambda_function.rb ${LAMBDA_TASK_ROOT}/

# Set the handler
CMD [ "lambda_function.lambda_handler" ]
