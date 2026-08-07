#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '../../Private/Invoke-SPCGraphBatch.ps1')
}

Describe 'Invoke-SPCGraphBatch Unit Tests' {

    Context 'Normal Operation' {
        It 'returns all sub-responses on successful batch request' {
            Mock Invoke-RestMethod {
                return [PSCustomObject]@{
                    responses = @(
                        [PSCustomObject]@{ id = '1'; status = 200; body = 'OK' },
                        [PSCustomObject]@{ id = '2'; status = 200; body = 'OK' }
                    )
                }
            }

            $requests = [System.Collections.Generic.List[hashtable]]::new()
            $requests.Add(@{ id = '1'; method = 'GET'; url = '/users/1' })
            $requests.Add(@{ id = '2'; method = 'GET'; url = '/users/2' })

            $res = Invoke-SPCGraphBatch -Requests $requests -AccessToken 'fake-token'
            $res.Count | Should -Be 2
            $res[0].status | Should -Be 200
            $res[1].status | Should -Be 200
        }
    }

    Context 'Envelope 429 Throttling' {
        It 'retries envelope 429 responses using Retry-After header or backoff and succeeds' {
            $script:callCount = 0
            Mock Start-Sleep {}

            Mock Invoke-RestMethod {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    $resp = [System.Net.HttpWebResponse]::new()
                    # Throw exception with StatusCode 429
                    $ex = [System.Management.Automation.MethodInvocationException]::new("429 Throttled")
                    $fakeResponse = [PSCustomObject]@{
                        StatusCode = 429
                        Headers = @{ 'Retry-After' = '1' }
                    }
                    $ex | Add-Member -MemberType NoteProperty -Name 'Response' -Value $fakeResponse -Force
                    throw $ex
                }
                return [PSCustomObject]@{
                    responses = @([PSCustomObject]@{ id = '1'; status = 200; body = 'OK' })
                }
            }

            $requests = [System.Collections.Generic.List[hashtable]]::new()
            $requests.Add(@{ id = '1'; method = 'GET'; url = '/users/1' })

            $res = Invoke-SPCGraphBatch -Requests $requests -AccessToken 'fake-token'
            $res.Count | Should -Be 1
            $res[0].status | Should -Be 200
            $script:callCount | Should -Be 2
        }

        It 'throws ERR-429 when envelope 429 retries exhaust max attempts' {
            Mock Start-Sleep {}

            Mock Invoke-RestMethod {
                $ex = [System.Management.Automation.MethodInvocationException]::new("429 Throttled")
                $fakeResponse = [PSCustomObject]@{ StatusCode = 429 }
                $ex | Add-Member -MemberType NoteProperty -Name 'Response' -Value $fakeResponse -Force
                throw $ex
            }

            $requests = [System.Collections.Generic.List[hashtable]]::new()
            $requests.Add(@{ id = '1'; method = 'GET'; url = '/users/1' })

            { Invoke-SPCGraphBatch -Requests $requests -AccessToken 'fake-token' } | Should -Throw -ExpectedMessage "*ERR-429*"
        }
    }

    Context 'Inner Sub-request 429 Throttling' {
        It 'retries inner 429 sub-requests and collects non-429 results across attempts' {
            $script:batchAttempt = 0
            Mock Start-Sleep {}

            Mock Invoke-RestMethod {
                $script:batchAttempt++
                if ($script:batchAttempt -eq 1) {
                    # First attempt: req 1 gets 200, req 2 gets 429 with Retry-After header
                    return [PSCustomObject]@{
                        responses = @(
                            [PSCustomObject]@{ id = '1'; status = 200; body = 'User1' },
                            [PSCustomObject]@{ id = '2'; status = 429; headers = @{ 'Retry-After' = '2' }; body = 'Throttled' }
                        )
                    }
                } else {
                    # Second attempt for req 2: gets 200
                    return [PSCustomObject]@{
                        responses = @(
                            [PSCustomObject]@{ id = '2'; status = 200; body = 'User2' }
                        )
                    }
                }
            }

            $requests = [System.Collections.Generic.List[hashtable]]::new()
            $requests.Add(@{ id = '1'; method = 'GET'; url = '/users/1' })
            $requests.Add(@{ id = '2'; method = 'GET'; url = '/users/2' })

            $res = Invoke-SPCGraphBatch -Requests $requests -AccessToken 'fake-token'
            $res.Count | Should -Be 2
            $script:batchAttempt | Should -Be 2
            
            $req1Res = $res | Where-Object { $_.id -eq '1' }
            $req2Res = $res | Where-Object { $_.id -eq '2' }
            $req1Res.status | Should -Be 200
            $req2Res.status | Should -Be 200
        }
    }

    Context 'AC-12 Security Guardrails' {
        It 'ensures no secrets or credentials appear in verbose or information streams' {
            Mock Start-Sleep {}
            Mock Invoke-RestMethod {
                return [PSCustomObject]@{
                    responses = @([PSCustomObject]@{ id = '1'; status = 200; body = 'OK' })
                }
            }

            $requests = [System.Collections.Generic.List[hashtable]]::new()
            $requests.Add(@{ id = '1'; method = 'GET'; url = '/users/1' })

            $verboseStream = [System.Collections.Generic.List[string]]::new()
            $infoStream = [System.Collections.Generic.List[string]]::new()

            Invoke-SPCGraphBatch -Requests $requests -AccessToken 'fake-token-value' -Verbose 4>&1 6>&1 | ForEach-Object {
                if ($_ -is [System.Management.Automation.VerboseRecord]) {
                    $verboseStream.Add($_.Message)
                } elseif ($_ -is [System.Management.Automation.InformationRecord]) {
                    $infoStream.Add($_.MessageData)
                }
            }

            foreach ($msg in $verboseStream) {
                $msg | Should -Not -Match 'password|secret|pfx|credential'
            }
            foreach ($msg in $infoStream) {
                $msg | Should -Not -Match 'password|secret|pfx|credential'
            }
        }
    }
}
