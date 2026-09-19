function Get-ResourceGroupState ($state) {
    switch ($state) {
        -1 { "Unknown" }
        0 { "Online" }
        1 { "Offline" }
        2 { "Failed" }
        3 { "PartialOnline" }
        4 { "Pending" }
        default { $state }
    }
}
