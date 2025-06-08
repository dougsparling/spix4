# Stage 1: Install Gems
FROM ruby:3.4.4-slim-bullseye AS gem_install_stage

WORKDIR /app

COPY Gemfile Gemfile.lock ./

RUN bundle install --jobs $(nproc) --retry 3 --without development test

# Stage 2: Build Application
FROM ruby:3.4.4-slim-bullseye

WORKDIR /app

# Copy gems from the previous stage
COPY --from=gem_install_stage /usr/local/bundle/ /usr/local/bundle/

# Copy application files
COPY . .

# Expose the port the application runs on
EXPOSE 8080

# Command to run the application
CMD ["bundle", "exec", "ruby", "websocket.rb"]
