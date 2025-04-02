FROM public.ecr.aws/lambda/ruby:3.2

# Install development tools needed for native extensions
RUN yum install -y gcc make git

# Set up the working directory
WORKDIR ${LAMBDA_TASK_ROOT}

# Copy dependency files
COPY Gemfile Gemfile.lock* ${LAMBDA_TASK_ROOT}/

RUN bundle config set --local path 'vendor/bundle' && \
    bundle install

# Copy function code
COPY lambda_function.rb ${LAMBDA_TASK_ROOT}/

# Set the handler
CMD [ "lambda_function.lambda_handler" ]
