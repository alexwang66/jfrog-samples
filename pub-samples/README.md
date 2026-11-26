# JFrog Pub sample

This is a minimal Dart Pub package that is built and published to JFrog Artifactory with the `jf` CLI.

## Local test

```bash
dart pub get
dart test
dart pub publish --dry-run
```

## Build and upload with `jf`

From this directory, run:

```bash
../scripts/build-and-upload-pub.sh
```

The script validates the package, creates the standard Pub archive layout, uploads it with `jf rt upload`, and publishes build-info with `jf rt build-publish`.

The sample was published to:

```text
https://solenglatest.jfrog.io/artifactory/pub-samples-local/jfrog_pub_sample/jfrog_pub_sample-0.1.0.tar.gz
```

The generated Pub metadata is available from:

```text
https://solenglatest.jfrog.io/artifactory/api/pub/pub-samples-local/api/packages/jfrog_pub_sample
```

## Publish with Flutter CLI

For the customer workflow, configure the Artifactory Pub endpoint and publish with Flutter:

```bash
export PUB_HOSTED_URL="https://solenglatest.jfrog.io/artifactory/api/pub/pub-samples-local"
dart pub token add "$PUB_HOSTED_URL" --env-var JF_ACCESS_TOKEN
flutter pub publish
```

The manual GitHub Actions workflow `.github/workflows/flutter-pub-publish.yml` runs the same flow with Flutter 3.50.0.

Environment variables:

- `JFROG_SERVER_ID` (default: `solenglatest`)
- `JFROG_PUB_REPO` (default: `pub-samples-local`)
- `JFROG_BUILD_NAME` (default: `jfrog-pub-sample`)
- `JFROG_BUILD_NUMBER` (default: package version from `pubspec.yaml`)
