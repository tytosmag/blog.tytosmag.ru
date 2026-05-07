FROM ruby:3.4-slim

WORKDIR /srv/jekyll

RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN git config --global --add safe.directory /srv/jekyll

COPY Gemfile Gemfile.lock ./

RUN bundle install

EXPOSE 4000
EXPOSE 35729

CMD ["bundle", "exec", "jekyll", "serve", "--host", "0.0.0.0", "--livereload", "--force_polling"]
