Function Remove-InvalidFileNameChars {
    param(
        [Parameter(Mandatory,
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName)]
        [String]$Name
    )

    # Cache invalid characters at script scope for performance optimization
    # Recommendation from dbatools.library PR #31
    if (-not $script:InvalidFileNameChars) {
        $script:InvalidFileNameChars = [IO.Path]::GetInvalidFileNameChars() -join ""
        $script:InvalidFileNameCharsPattern = "[{0}]" -f [RegEx]::Escape($script:InvalidFileNameChars)
    }

    return ($Name -replace $script:InvalidFileNameCharsPattern)
}