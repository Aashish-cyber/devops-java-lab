FROM tomcat:10.1-jdk21-temurin

LABEL org.opencontainers.image.source="https://github.com/Aashish-cyber/devops-java-lab"

COPY target/devops-lab-1.0.war /usr/local/tomcat/webapps/devops-lab.war

EXPOSE 8080