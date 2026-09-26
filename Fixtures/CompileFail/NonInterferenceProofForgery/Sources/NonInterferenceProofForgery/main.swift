import Foundation
import Swiftest

let digest = try Digest.sha256(Data("untrusted".utf8))
let proof = NonInterferenceProof<BuildConfiguration>.verified(certificate: digest)
print(proof.certificate.rawValue)
