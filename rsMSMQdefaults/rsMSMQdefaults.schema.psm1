Configuration rsMSMQdefaults {
    param
    (
        [parameter(Mandatory = $true)]
        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure,
        [System.String]
        $PullServerAddress = $env:COMPUTERNAME

    )
    Import-DSCResource -ModuleName xWebAdministration
    Import-DSCResource -ModuleName rsMSMQ
    Import-DscResource -ModuleName rsScheduledTask
    Import-DSCResource -ModuleName PowerShellAccessControl
    Node $env:COMPUTERNAME
    {
        WindowsFeature MSMQ {
            Name = "MSMQ"
            IncludeAllSubFeature = $true
            Ensure = $Ensure
        }
        File MSMQredirect{
            Ensure = 'Present'
            Type = 'File'
            DestinationPath = 'C:\Windows\system32\msmq\Mapping\msmqredirect.xml'
            DependsOn = "[WindowsFeature]MSMQ"
            Contents = "
                <redirections xmlns='msmq-queue-redirections.xml'>
                  <redirection>
                      <from>https://$PullServerAddress/msmq/private$/rsdsc</from>
                      <to>http://$($env:COMPUTERNAME)/msmq/private$/rsdsc</to> 
                  </redirection>
                </redirections>"
        } 
        xWebsite DefaultSite
        {
            Ensure = 'Present'
            Name = 'Default Web Site'
            State = 'Started'
            PhysicalPath = "C:\inetpub\wwwroot"
            BindingInfo = @(
                    MSFT_xWebBindingInformation
                    {
                        IPAddress = '*'
                        HostName = $PullServerAddress
                        Port = 443
                        Protocol = 'HTTPS'
                        CertificateThumbprint = (Get-ChildItem Cert:\LocalMachine\My\ | Where-Object {$_.Subject -eq $('CN=', $PullServerAddress -join '')}).Thumbprint
                    }
                    MSFT_xWebBindingInformation
                    {
                        IPAddress = '*'
                        HostName = $env:COMPUTERNAME
                        Port = 80
                        Protocol = 'HTTP'
                    }
            )
            DependsOn = "[WindowsFeature]MSMQ"
        }
        rsCreateQueue MSMQrsdsc {
            QueueName = 'rsdsc'
            Ensure = $Ensure
            DependsOn = '[xWebsite]DefaultSite'
        }
        rsScheduledTask MSMQTrigger
        {
            Name          = "MSMQTrigger"
            Ensure        = "Present"
            ActionParams  = @{
                                "Execute" = "$pshome\powershell.exe";
                                "Argument" = "-Command Start-DSCConfiguration -UseExisting -Wait";
                            }
            TriggerParams = @{
                                "Once" = "True";
                                "RepetitionInterval" = "01:00:00";
                            }
        }
        cAccessControlEntry RXMSMQTrigger
        {
            Ensure = $Ensure
            Path = 'C:\Windows\System32\Tasks\MSMQTrigger'
            AceType = "AccessAllowed"
            ObjectType = "File"
            AccessMask = ([System.Security.AccessControl.FileSystemRights]::ReadAndExecute)
            Principal = 'NT AUTHORITY\NETWORK SERVICE'
            DependsOn = @('[rsScheduledTask]MSMQTrigger')
        }
        rsTrigAdm DownloadTrigAdm {
            Ensure = $Ensure
        }
        rsTriggerRule AddTriggerRule{
            QueueName = 'rsdsc'
            TriggerName = 'MSMQTrigger'
            RuleName = 'StartDSC'
            RuleCondition = '$MSG_LABEL_CONTAINS=execute'
            RuleAction = "EXE$("`t")C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe$("`t" + "\" + '"')-Command$("\" + '"' + "`t" + "\" + '"')Get-ScheduledTask -TaskName MSMQTrigger | Start-ScheduledTask$("\" + '"' + "`t")"
            Ensure = $Ensure
            DependsOn = '[rsTrigAdm]DownloadTrigAdm'
        }
        script nodesFile {
            GetScript = {
                return @{ 'Result' = $true }
            }
     
            TestScript = {
                if(Test-Path -Path $(Join-Path $([Environment]::GetEnvironmentVariable('defaultPath','Machine')) -ChildPath 'nodes.json')) {
                    return $true
                }
                else {
                    return $false
                }
            }
     
            SetScript = {
                if(!(Test-Path -Path $(Join-Path $([Environment]::GetEnvironmentVariable('defaultPath','Machine')) -ChildPath 'nodes.json'))) {
                    Set-Content -Path $(Join-Path $([Environment]::GetEnvironmentVariable('defaultPath','Machine')) -ChildPath 'nodes.json') -Value $(@{"Nodes" = @()} | ConvertTo-Json)
                }
                Restart-Service MSMQ -Force
            }
        }      
        rsProcessQueue PublicCertNodesJSon {
            QueueName = 'rsdsc'
            scavengeTime = 3
        }
    }

}
