function Get-ResourceState ($state) {
    switch ($state) {
        -1 { "Unknown" }
        0 { "Inherited" }
        1 { "Initializing" }
        2 { "Online" }
        3 { "Offline" }
        4 { "Failed" }
        128 { "Pending" }
        129 { "Online Pending" }
        130 { "Offline Pending" }
    }
}