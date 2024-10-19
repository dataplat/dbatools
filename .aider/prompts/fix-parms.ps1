<# loop through all files in the tests directory that matches HaveParameter
$tests = Get-ChildItem -Path /workspace/tests -Filter *.Tests.ps1

$prompt = "When testing HaveParameter, we should have used type full names and we used type short names.Consult types.md and apply the appropriate replacements. Do not remove any arrays ([]), just replace the type names."


foreach ($test in $tests) {
    Write-Host "Processing $test"
    aider --message "$prompt" --file $test.FullName --model azure/gpt-4o-mini --no-stream --cache-prompts --read /workspace/.aider/prompts/types.md
}

$tests = Get-ChildItem -Path /workspace/tests -Filter *.Tests.ps1

$prompt = "This is a Pester v5 test suite. 1. Remove -Type test in HaveParameter tests. 2. Remove -Mandatory test in HaveParameter test. 2. Remove all -Mandatory:`$false from the HaveParameter test."


foreach ($test in $tests) {
    Write-Host "Processing $test"
    aider --message "$prompt" --file $test.FullName --model azure/gpt-4o-mini --no-stream
}
#>

$tests = Get-ChildItem -Path /workspace/tests -Filter *.Tests.ps1

$prompt = 'All HaveParameter tests must be grouped into ONE It block titled "has all the required parameters". Like this:

        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }'


foreach ($test in $tests) {
    Write-Host "Processing $test"
    if ((Get-Content $test.FullName | Select-String -SimpleMatch -Pattern 'Should -HaveParameter $param')) {
        Write-Host "Skipping $($test.Name) because it already has the correct structure"
        continue
    }
    aider --message "$prompt" --file $test.FullName --model azure/gpt-4o-mini --no-stream
}