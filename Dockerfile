# Stage 1: Install Gems
FROM ruby:3.4.4-slim-bullseye AS gem_install_stage
WORKDIR /app

# Install build dependencies for websockets (openssl + dev tools)
# Important to do this before copying Gemfile for caching 
RUN apt-get update && \
    apt-get install -y g++ gcc make musl-dev libssl-dev && \
    rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle config set without 'development test'
RUN bundle install --jobs $(nproc) --retry 3

# Stage 2: Build Application
FROM ruby:3.4.4-slim-bullseye
WORKDIR /app

# Copy gems from the previous stage
COPY --from=gem_install_stage /usr/local/bundle/ /usr/local/bundle/

ADD static /app/static
ADD data /app/data
COPY Gemfile* *.rb config.ru ./
EXPOSE 8080
CMD ["bundle", "exec", "thin", "start", "-e", "production"]