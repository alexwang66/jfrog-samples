package curation.policies

import rego.v1

app_version := input.data.applications.getApplicationVersion

application_evidence := [predicate |
    predicate := app_version.application.evidenceSubject.evidenceConnection.edges[_].node
]

version_evidence := [predicate |
    predicate := app_version.evidenceSubject.evidenceConnection.edges[_].node
]

source_evidence := [predicate |
    source := app_version.sources[_]
    predicate := source.evidenceSubject.evidenceConnection.edges[_].node
]

artifact_evidence := [predicate |
    releasable := app_version.releasables.releasablesConnection.edges[_].node
    artifact := releasable.artifacts[_]
    predicate := artifact.evidenceSubject.evidenceConnection.edges[_].node
]

all_evidence := array.concat(
    array.concat(application_evidence, version_evidence),
    array.concat(source_evidence, artifact_evidence),
)

default exists := false

exists if {
    some predicate in all_evidence
    predicate.predicateType == "https://jfrog.com/evidence/security-scan/v1"
}

allow := {
    "should_allow": exists,
    "message": "Required security-scan evidence was not found",
}
