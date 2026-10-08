# Third-party notices

MaterialView by Oskar Groth

Source: https://github.com/OskarGroth/MaterialView
Revision: b3a04ce56eca69d388c48e9621ce61778fe976c7
License: MIT, reproduced in Vendor/MaterialView/LICENSE.

Only the AppKit implementation and its small Objective-C declarations are included. It uses non-public Core Animation rendering interfaces; this build is not suitable for direct Mac App Store submission.

Local integration retains the CACornerMask.all helper from the upstream SwiftUI wrapper in the AppKit source; the SwiftUI wrapper is not bundled.
