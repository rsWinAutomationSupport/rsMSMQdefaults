rsMSMQdefaults
=====

This module contains the MSMQ default settings needed for a DSC pull-server using MSMQ.

rsMSMQdefaults
=====


```PoSh
rsMSMQdefaults MyMSMQ
        {
            Ensure = 'Present'
            PullServerAddress = $d.PullServerAddress
            DependsOn = '[File]rsPlatformDir', '[rsPullCert]MonitorPullServerCert' 
        }
}
```

