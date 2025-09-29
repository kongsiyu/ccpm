#!/bin/bash
# Run tests based on project type

# Look for test commands based on project type
if [ -f package.json ]; then
  npm test || echo "⚠️ Tests failed. Continue anyway? (yes/no)"
elif [ -f pom.xml ]; then
  mvn test || echo "⚠️ Tests failed. Continue anyway? (yes/no)"
elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
  ./gradlew test || echo "⚠️ Tests failed. Continue anyway? (yes/no)"
elif [ -f composer.json ]; then
  ./vendor/bin/phpunit || echo "⚠️ Tests failed. Continue anyway? (yes/no)"
elif [ -f *.sln ] || [ -f *.csproj ]; then
  dotnet test || echo "⚠️ Tests failed. Continue anyway? (yes/no)"
elif [ -f Cargo.toml ]; then
  cargo test || echo "⚠️ Tests failed. Continue anyway? (yes/no)"
elif [ -f go.mod ]; then
  go test ./... || echo "⚠️ Tests failed. Continue anyway? (yes/no)"
elif [ -f Gemfile ]; then
  bundle exec rspec || bundle exec rake test || echo "⚠️ Tests failed. Continue anyway? (yes/no)"
elif [ -f pubspec.yaml ]; then
  flutter test || echo "⚠️ Tests failed. Continue anyway? (yes/no)"
elif [ -f Package.swift ]; then
  swift test || echo "⚠️ Tests failed. Continue anyway? (yes/no)"
elif [ -f CMakeLists.txt ]; then
  cd build && ctest || echo "⚠️ Tests failed. Continue anyway? (yes/no)"
elif [ -f Makefile ]; then
  make test || echo "⚠️ Tests failed. Continue anyway? (yes/no)"
else
  echo "ℹ️ No recognized test framework found, skipping tests"
fi