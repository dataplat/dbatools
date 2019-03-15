function Get-DbaRandomizedDataset {
    [CmdLetBinding()]
    param(
        [string]$Template,
        [string]$TemplateFile,
        [int]$Rows = 100,
        [string]$Locale = 'en',
        [switch]$EnableException
    )

    begin {
        # Create the faker objects
        Add-Type -Path (Resolve-Path -Path "$script:PSModuleRoot\bin\randomizer\Bogus.dll")
        $faker = New-Object Bogus.Faker($Locale)

        # Check variables
        if (-not $Template -and -not $TemplateFile) {
            Stop-Function -Message "Please enter a template or assign a template file" -Continue
        }

        # Get all thee templates
        if ($Template) {
            $templates = Get-ChildItem (Resolve-Path -Path "$script:PSModuleRoot\bin\randomizer\templates\*.json")

            if ($Template -in $templates.BaseName) {
                $TemplateFile = $templates | Where-Object BaseName -eq $Template | Select-Object FullName -ExpandProperty FullName
            } else {
                Stop-Function -Message "Could not find template with name $Template" -Continue
            }
        }
    }

    process {
        if (Test-FunctionInterrupt) { return }

        # Get all the items that should be processed
        try {
            $dataset = Get-Content -Path $TemplateFile -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Stop-Function -Message "Could not parse template file" -ErrorRecord $_ -Target $TemplateFile
            return
        }

        $result = @()

        for ($i = 1; $i -le $Rows; $i++) {
            $row = New-Object PSCustomObject

            foreach ($column in $dataset.Columns) {
                $value = Get-DbaRandomizedValue -RandomizerType $column.Type -RandomizerSubType $column.SubType

                $row | Add-Member -Name $column.Name -Type NoteProperty -Value $value

            }

            $result += $row

        }

        $result
    }
}