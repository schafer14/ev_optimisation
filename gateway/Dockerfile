FROM golang:1.26 AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 go build -o /gateway .

FROM gcr.io/distroless/static
COPY --from=build /gateway /gateway
EXPOSE 7777
ENTRYPOINT ["/gateway"]
