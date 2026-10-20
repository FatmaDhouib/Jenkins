FROM eclipse-temurin:17-jre
EXPOSE 8080
WORKDIR /app
COPY target/app-built.jar app.jar
CMD ["java", "-jar", "app.jar"]
