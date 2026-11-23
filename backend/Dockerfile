# One Dockerfile for every Spring Boot service:  docker build --build-arg MODULE=ms-donors -t ms-donors .
# Stage 1 compiles with Maven, stage 2 only carries the JRE + the fat JAR.
FROM maven:3-eclipse-temurin-21 AS build
ARG MODULE
WORKDIR /src
COPY . .
RUN mvn -B -q -pl ${MODULE} -am package -DskipTests

FROM eclipse-temurin:21-jre
ARG MODULE
RUN useradd --system --uid 10001 yawar
COPY --from=build /src/${MODULE}/target/${MODULE}.jar /app/app.jar
USER yawar
EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-XX:+ExitOnOutOfMemoryError", "-jar", "/app/app.jar"]
