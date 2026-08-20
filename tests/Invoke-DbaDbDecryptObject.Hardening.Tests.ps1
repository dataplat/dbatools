#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }

Describe "Invoke-DbaDbDecryptObject hardening" -Tag UnitTests {
    BeforeAll {
        $dbatoolsModule = $null
        foreach ($candidate in @(Get-Module dbatools | Where-Object ModuleType -eq "Script")) {
            $hasPrivateFunction = $false
            try {
                $hasPrivateFunction = & $candidate { [bool](Get-Command ConvertFrom-EncryptedObjectChunk -ErrorAction SilentlyContinue) }
            } catch {
                $hasPrivateFunction = $false
            }
            if ($hasPrivateFunction) {
                $dbatoolsModule = $candidate
                break
            }
        }
        if ($null -eq $dbatoolsModule) {
            throw "No loaded dbatools script module exposes ConvertFrom-EncryptedObjectChunk."
        }

        $familyGuid = [guid]"7e11756e-abe9-11d2-896a-00c04fd9374a"
        $objectId = 1253579504

        function New-TestCipherChunk {
            param(
                [int]$ColId,
                [string]$Text
            )

            $plainText = [System.Text.Encoding]::Unicode.GetBytes($Text)
            $keystreamParams = @{
                FamilyGuid = $familyGuid
                ObjectId   = $objectId
                ColId      = $ColId
                Length     = $plainText.Length
            }
            $keystream = & $dbatoolsModule { param($p) Get-EncryptedObjectKeystream @p } $keystreamParams

            $cipher = New-Object byte[] $plainText.Length
            for ($offset = 0; $offset -lt $plainText.Length; $offset++) {
                $cipher[$offset] = $plainText[$offset] -bxor $keystream[$offset]
            }

            [PSCustomObject]@{
                ColId  = $ColId
                Cipher = $cipher
            }
        }

        function Convert-TestCipherChunk {
            param([object[]]$Chunk)

            $params = @{
                FamilyGuid = $familyGuid
                ObjectId   = $objectId
                Chunk      = $Chunk
            }
            & $dbatoolsModule { param($p) ConvertFrom-EncryptedObjectChunk @p } $params
        }
    }

    It "refuses duplicate colids rather than concatenating ambiguous ciphertext" {
        $chunk = @(
            (New-TestCipherChunk -ColId 1 -Text "SELECT 1;"),
            (New-TestCipherChunk -ColId 1 -Text "SELECT 2;")
        )

        { Convert-TestCipherChunk -Chunk $chunk } | Should -Throw -ExpectedMessage "*more than one ciphertext chunk with colid 1*"
    }

    It "refuses a chunk whose ciphertext is null" {
        $chunk = @(
            [PSCustomObject]@{
                ColId  = 1
                Cipher = $null
            }
        )

        { Convert-TestCipherChunk -Chunk $chunk } | Should -Throw -ExpectedMessage "*has no ciphertext*"
    }

    It "still decrypts a valid chunk exactly" {
        $text = "CREATE PROCEDURE dbo.Valid WITH ENCRYPTION AS SELECT 1;"
        $chunk = @(New-TestCipherChunk -ColId 1 -Text $text)

        Convert-TestCipherChunk -Chunk $chunk | Should -BeExactly $text
    }
}
