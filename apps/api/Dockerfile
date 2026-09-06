FROM golang:1.24-alpine AS development

WORKDIR /workspace

RUN apk add --no-cache ca-certificates tzdata

COPY go.mod go.sum ./
RUN go mod download

COPY . .


FROM development AS builder

ARG TARGETOS=linux
ARG TARGETARCH

RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /out/server \
    ./cmd/server

FROM golang:1.24-alpine AS migration-builder

ARG GOOSE_VERSION=v3.24.1

RUN apk add --no-cache ca-certificates

RUN GOBIN=/out CGO_ENABLED=0 go install \
    github.com/pressly/goose/v3/cmd/goose@${GOOSE_VERSION}

FROM alpine:3.22 AS migration

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

COPY --from=migration-builder /out/goose /usr/local/bin/goose
COPY db/migrations /app/migrations


ENTRYPOINT ["sh", "-c"]
CMD ["goose -dir /app/migrations postgres \"$DATABASE_URL\" up"]

FROM gcr.io/distroless/static-debian12:nonroot AS production

WORKDIR /app

COPY --from=builder /out/server /app/server

EXPOSE 8080

USER nonroot:nonroot

ENTRYPOINT ["/app/server"]

