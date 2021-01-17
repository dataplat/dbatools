Import-Module ".\dbatools.psd1"

Find-DbaCommand -Rebuild

Import-Module HelpOut
Install-Maml -FunctionRoot functions,internal\functions -Module dbatools -Compact -NoVersion -Verbose

Save-DbaDiagnosticQueryScript -Path ".\bin\diagnosticquery"
