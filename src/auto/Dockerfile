# Build stage
FROM gradle:9.3-jdk21 AS build
WORKDIR /app
COPY gradle/ gradle/
COPY gradlew build.gradle settings.gradle ./
RUN ./gradlew dependencies --no-daemon
COPY src/ src/
RUN ./gradlew build --no-daemon


# Runtime stage
FROM eclipse-temurin:21.0.9_10-jre-alpine-3.22

RUN addgroup --system app && adduser --system --ingroup app app
WORKDIR /app
COPY --from=build /app/build/libs/*.jar app.jar
RUN chown app:app app.jar
USER app

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"] 

ADD --chmod=644 https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar /app/opentelemetry-javaagent.jar
ENV JAVA_TOOL_OPTIONS=-javaagent:/app/opentelemetry-javaagent.jar
