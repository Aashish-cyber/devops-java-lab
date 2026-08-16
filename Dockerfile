FROM tomcat:10.1-jdk21-temurin

COPY target/devops-lab-1.0.war /usr/local/tomcat/webapps/devops-lab.war

EXPOSE 8080
