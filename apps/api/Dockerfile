FROM maven:3.9.11-eclipse-temurin-21 AS build
WORKDIR /app
COPY apps/api/pom.xml ./pom.xml
COPY apps/api/src ./src
RUN mvn -B verify

FROM eclipse-temurin:21-jre-jammy AS runtime
WORKDIR /app
RUN groupadd --gid 10001 app && useradd --uid 10001 --gid app --no-create-home app
COPY --from=build /app/target/payments-api-0.1.0-SNAPSHOT.jar ./api.jar
USER app
ENV SERVER_PORT=8080
EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "/app/api.jar"]
