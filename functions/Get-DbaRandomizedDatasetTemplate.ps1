function Get-DbaRandomizedDatasetTemplate {

    param(
        [string[]]$Template,
        [string[]]$Path,
        [switch]$ExcludeDefault,
        [switch]$EnableException
    )

    begin {
        $templates = @()

        # Get all the default templates
        if (-not $ExcludeDefault) {
            $templates += Get-ChildItem (Resolve-Path -Path "$script:PSModuleRoot\bin\randomizer\templates\*.json")
        }
    }

    process {
        if (Test-FunctionInterrupt) { return}

        # Get the templates from the file path
        foreach ($p in $Path) {
            $templates += Get-ChildItem (Resolve-Path -Path "$Path\*.json")
        }

        # Filter the template if neccesary
        if ($Template) {
            $templates = $templates | Where-Object BaseName -in $Template
        }

        $templates | Select-Object BaseName, FullName
    }
}