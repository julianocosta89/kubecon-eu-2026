# Build stage
FROM gradle:9.7-jdk25 AS build
WORKDIR /app
COPY gradle/ gradle/
COPY gradlew build.gradle settings.gradle ./
RUN ./gradlew dependencies --no-daemon
COPY src/ src/
RUN ./gradlew bootJar --no-daemon


# Extraction stage: split the Boot jar into cache-friendly layers
FROM eclipse-temurin:25.0.4_7-jre-alpine-3.23 AS extract
WORKDIR /app
COPY --from=build /app/build/libs/*.jar app.jar
RUN java -Djarmode=tools -jar app.jar extract --layers --destination extracted


# Runtime stage
FROM eclipse-temurin:25.0.4_7-jre-alpine-3.23

RUN addgroup --system app && adduser --system --ingroup app app
WORKDIR /app
COPY --from=extract /app/extracted/dependencies/ ./
COPY --from=extract /app/extracted/spring-boot-loader/ ./
COPY --from=extract /app/extracted/snapshot-dependencies/ ./
COPY --from=extract /app/extracted/application/ ./
USER app

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "application.jar"]
