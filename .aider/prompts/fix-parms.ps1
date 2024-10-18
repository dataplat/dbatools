# loop through all files in the tests directory that matches HaveParameter
$tests = Get-ChildItem -Path /workspace/tests -Filter *.Tests.ps1

$prompt = "When testing HaveParameter, we should have used type full names and we used type short names.Consult types.md and apply the appropriate replacements. Do not remove any arrays ([]), just replace the type names."


foreach ($test in $tests) {
    Write-Host "Processing $test"
    aider --message "$prompt" --file $test.FullName --model azure/gpt-4o-mini --no-stream --cache-prompts --read /workspace/.aider/prompts/types.md
}
