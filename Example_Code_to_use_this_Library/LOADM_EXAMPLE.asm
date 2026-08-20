************************************************************************
* Generic LOADM example. TESTPROG.BIN must not overwrite this loader while
* DiskLibLoadM is running. Its DECB postamble EXEC address is returned in D.
************************************************************************
        ORG     $2000

Start:
        LDS     #$7FFF
        LDX     #LoadFilename
        LDD     #0                      * signed relocation offset
        JSR     DiskLibLoadM
        BCS     LoadFailed              * B = DiskError... value
        STD     LoadedExec
        JSR     DiskLibShutdown
        JMP     [LoadedExec]

LoadFailed:
        STB     LastDiskError
        JSR     DiskLibShutdown
LoadHalt:
        BRA     LoadHalt

LoadFilename:
        FCN     /TESTPROG.BIN:0/
LoadedExec:
        RMB     2
LastDiskError:
        RMB     1

        INCLUDE ../../Generic_6809_Libraries/DECB_Disk_File_Library.asm
        END     Start
