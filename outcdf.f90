! Conformal Cubic Atmospheric Model
    
! Copyright 2015 Commonwealth Scientific Industrial Research Organisation (CSIRO)
    
! This file is part of the Conformal Cubic Atmospheric Model (CCAM)
!
! CCAM is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! CCAM is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with CCAM.  If not, see <http://www.gnu.org/licenses/>.

!------------------------------------------------------------------------------

! CCAM netCDF output routines

! itype=1     write outfile history file (compressed)
! itype=-1    write restart file (uncompressed)
! localhist=f single processor output 
! localhist=t parallel output for each processor

! Thanks to Paul Ryan for advice on output netcdf routines.
    
module outcdf
    
private
public outfile, freqfile, mslp

character(len=3), dimension(12), parameter :: month = (/'jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'/)

contains

subroutine outfile(iout,rundate,nwrite,nstagin,jalbfix,nalpha,mins_rad)
      
use arrays_m
use cc_mpi
use pbl_m
use soilsnow_m ! tgg,wb,snowd
use tracers_m
      
implicit none
      
include 'newmpar.h'
include 'dates.h'    ! mtimer
include 'filnames.h' ! list of files, read in once only
include 'parm.h'

integer iout,nwrite,nstagin
integer, intent(in) :: jalbfix,nalpha,mins_rad
character(len=160) :: co2out,radonout,surfout
character(len=20) :: qgout
character(len=8) :: rundate

call START_LOG(outfile_begin)
      
if ( myid==0 ) then
  write(6,*) "ofile written for iout: ",iout
  write(6,*) "kdate,ktime,mtimer:     ",kdate,ktime,mtimer
end if

if ( nrungcm==-2 .or. nrungcm==-3 .or. nrungcm==-5 ) then
  if ( ktau==nwrite/2 .or. ktau==nwrite ) then
!        usually after first 24 hours, save soil variables for next run
    if ( ktau==nwrite ) then  ! 24 hour write
      if ( ktime==1200 ) then
        co2out=co2_12     ! 'co2.1200'
        radonout=radon_12 ! 'radon.1200'
        surfout=surf_12   ! 'current.1200'
        qgout='qg_12'
      else
        co2out=co2_00     !  'co2.0000'
        radonout=radon_00 ! 'radon.0000'
        surfout=surf_00   ! 'current.0000'
        qgout='qg_00'
      endif
    else                    ! 12 hour write
      if(ktime==1200)then
        co2out=co2_00     !  'co2.0000'
        radonout=radon_00 ! 'radon.0000'
        surfout=surf_00   ! 'current.0000'
        qgout='qg_00'
      else
        co2out=co2_12     ! 'co2.1200'
        radonout=radon_12 ! 'radon.1200'
        surfout=surf_12   ! 'current.1200'
        qgout='qg_12'
      endif
    endif               ! (ktau.eq.nwrite)
    if ( myid == 0 ) then
      write(6,*) "writing current soil & snow variables to ",surfout
      open(unit=77,file=surfout,form='formatted',status='unknown')
      write (77,*) kdate,ktime,' ktau = ',ktau
    end if
    call writeglobvar(77, wb, fmt='(14f6.3)')
    call writeglobvar(77, tgg, fmt='(12f7.2)')
    call writeglobvar(77, tss, fmt='(12f7.2)')
    call writeglobvar(77, snowd, fmt='(12f7.1)')
    call writeglobvar(77, sicedep, fmt='(12f7.1)')
    if ( myid == 0 ) close (77)
    if ( nrungcm==-2 .or. nrungcm==-5 ) then
      if ( myid == 0 ) then
        write(6,*) "writing special qgout file: ",qgout
        open(unit=77,file=qgout,form='unformatted',status='unknown')
      end if
      call writeglobvar(77, qg)
      if ( myid == 0 ) close (77)
    endif  ! (nrungcm.eq.-2.or.nrungcm.eq.-5)
  endif    ! (ktau.eq.nwrite/2.or.ktau.eq.nwrite)
endif      ! (nrungcm.eq.-2.or.nrungcm.eq.-3.or.nrungcm.eq.-5)

!---------------------------------------------------------------------------
if ( iout==19 ) then
  select case(io_rest)  
    case(1)  ! for netCDF 
      if ( myid==0 ) write(6,*) "restart write of data to netCDF"
      call cdfout(rundate,-1,nstagin,jalbfix,nalpha,mins_rad)
    case(3)
      write(6,*) "Error, restart binary output not supported"
      call ccmpi_abort(-1)
  end select
else
  select case(io_out)
    case(1)
      call cdfout(rundate,1,nstagin,jalbfix,nalpha,mins_rad)
    case(3)
      write(6,*) "Error, history binary output not supported"
      call ccmpi_abort(-1)
  end select
end if

call END_LOG(outfile_end)
      
return
end subroutine outfile

    
!--------------------------------------------------------------
! CONFIGURE DIMENSIONS FOR OUTPUT NETCDF FILES
subroutine cdfout(rundate,itype,nstagin,jalbfix,nalpha,mins_rad)

use aerosolldr                        ! LDR prognostic aerosols
use cable_ccam, only : proglai        ! CABLE
use cc_mpi                            ! CC MPI routines
use cloudmod                          ! Prognostic cloud fraction
use infile                            ! Input file routines
use liqwpar_m                         ! Cloud water mixing ratios
use mlo, only : mindep              & ! Ocean physics and prognostic arrays
    ,minwater,mxd,zomode,zoseaice   &
    ,factchseaice
use mlodynamics                       ! Ocean dynamics
use parmhdff_m                        ! Horizontal diffusion parameters
use seaesfrad_m                       ! SEA-ESF radiation
use tkeeps                            ! TKE-EPS boundary layer
use tracers_m                         ! Tracer data

implicit none

include 'newmpar.h'                   ! Grid parameters
include 'dates.h'                     ! Date data
include 'filnames.h'                  ! Filenames
include 'kuocom.h'                    ! Convection parameters
include 'parm.h'                      ! Model configuration
include 'parmdyn.h'                   ! Dynamics parameters
include 'parmgeom.h'                  ! Coordinate data
include 'parmhor.h'                   ! Horizontal advection parameters
include 'parmsurf.h'                  ! Surface parameters

integer ixp,iyp,idlev,idnt,idms,idoc
integer leap
common/leap_yr/leap                   ! Leap year (1 to allow leap years)
integer nbarewet,nsigmf
common/nsib/nbarewet,nsigmf

integer, parameter :: nihead=54
integer, parameter :: nrhead=14
integer, dimension(nihead) :: nahead
integer, dimension(4), save :: dima,dims,dimo
integer, intent(in) :: jalbfix,nalpha,mins_rad
integer itype, nstagin, tlen
integer xdim, ydim, zdim, tdim, msdim, ocdim
integer icy, icm, icd, ich, icmi, ics, idv
integer namipo3
integer, save :: idnc=0, iarch=0
real, dimension(nrhead) :: ahead
character(len=180) cdffile
character(len=33) grdtim
character(len=20) timorg
character(len=8) rundate

! Determine file names depending on output
if ( myid==0 .or. localhist ) then
  ! File setup follows
  if ( itype==1 ) then
    ! itype=1 outfile
    iarch=iarch+1
    if ( localhist ) then
      write(cdffile,"(a,'.',i6.6)") trim(ofile), myid
    else
      cdffile=ofile
    endif
  else
    ! itype=-1 restfile
    iarch=1
    if ( localhist ) then
      write(cdffile,"(a,'.',i6.6)") trim(restfile), myid
    else
      cdffile=restfile
    endif
    idnc=0
  endif ! ( itype==1)then

  ! Open new file
  if( iarch==1 )then
    if ( myid==0 ) write(6,'(" nccre of itype,cdffile=",i5," ",a80)') itype,cdffile
    call ccnf_create(cdffile,idnc)
    ! Turn off the data filling
    call ccnf_nofill(idnc)
    ! Create dimensions, lon, runtopo.shlat
    if( localhist ) then
      call ccnf_def_dim(idnc,'longitude',il,xdim)
      call ccnf_def_dim(idnc,'latitude',jl,ydim)
    else
      call ccnf_def_dim(idnc,'longitude',il_g,xdim)
      call ccnf_def_dim(idnc,'latitude',jl_g,ydim)
    endif
    call ccnf_def_dim(idnc,'lev',kl,zdim)
    call ccnf_def_dim(idnc,'zsoil',ms,msdim)
    if ( abs(nmlo)>0. .and. abs(nmlo)<=9 ) then
      call ccnf_def_dim(idnc,'olev',ol,ocdim)
    else
      ocdim = 0
    end if
    if ( unlimitedhist ) then
      call ccnf_def_dimu(idnc,'time',tdim)
    else
      if ( itype==-1 ) then
        tlen = 1 ! restart
      else if ( mod(ntau,nwt)==0 ) then
        tlen = ntau/nwt      ! nwt is a factor of ntau
        if ( nwt>0 ) then
          tlen = tlen + 1    ! save zero time-step
        end if        
      else
        tlen = ntau/nwt + 1  ! nwt is not a factor of ntau
        if ( nwt>0 ) then
          tlen = tlen + 1    ! save zero time-step
        end if        
      end if
      call ccnf_def_dim(idnc,'time',tlen,tdim)
    end if
    if ( myid==0 ) then
      write(6,*) "xdim,ydim,zdim,tdim"
      write(6,*)  xdim,ydim,zdim,tdim
    end if

    ! atmosphere dimensions
    dima = (/ xdim, ydim, zdim, tdim /)

    ! soil dimensions
    dims = (/ xdim, ydim, msdim, tdim /)

    ! ocean dimensions
    dimo = (/ xdim, ydim, ocdim, tdim /)

    ! Define coords.
    call ccnf_def_var(idnc,'longitude','float',1,dima(1:1),ixp)
    call ccnf_put_att(idnc,ixp,'point_spacing','even')
    call ccnf_put_att(idnc,ixp,'units','degrees_east')
    call ccnf_def_var(idnc,'latitude','float',1,dima(2:2),iyp)
    call ccnf_put_att(idnc,iyp,'point_spacing','even')
    call ccnf_put_att(idnc,iyp,'units','degrees_north')
    if ( myid==0 ) write(6,*) 'ixp,iyp=',ixp,iyp

    call ccnf_def_var(idnc,'lev','float',1,dima(3:3),idlev)
    call ccnf_put_att(idnc,idlev,'positive','down')
    call ccnf_put_att(idnc,idlev,'point_spacing','uneven')
    call ccnf_put_att(idnc,idlev,'units','sigma_level')
    call ccnf_put_att(idnc,idlev,'long_name','sigma_level')
    if (myid==0) write(6,*) 'idlev=',idlev

    call ccnf_def_var(idnc,'zsoil','float',1,dims(3:3),idms)
    call ccnf_put_att(idnc,idms,'point_spacing','uneven')
    call ccnf_put_att(idnc,idms,'units','m')
    if (myid==0) write(6,*) 'idms=',idms
        
    if (abs(nmlo)>0.and.abs(nmlo)<=9) then
      call ccnf_def_var(idnc,'olev','float',1,dimo(3:3),idoc)
      call ccnf_put_att(idnc,idoc,'point_spacing','uneven')
      call ccnf_put_att(idnc,idoc,'units','sigma_level')
      if (myid==0) write(6,*) 'idoc=',idoc
    end if

    call ccnf_def_var(idnc,'time','float',1,dima(4:4),idnt)
    call ccnf_put_att(idnc,idnt,'point_spacing','even')
    if ( myid==0 ) then
      write(6,*) 'tdim,idnc=',tdim,idnc
      write(6,*) 'idnt=',idnt
      write(6,*) 'kdate,ktime,ktau=',kdate,ktime,ktau
    end if

    icy = kdate/10000
    icm = max(1, min(12, (kdate-icy*10000)/100))
    icd = max(1, min(31, (kdate-icy*10000-icm*100)))
    if ( icy<100 ) icy = icy + 1900
    ich = ktime/100
    icmi = (ktime-ich*100)
    ics = 0
    write(timorg,'(i2.2,"-",a3,"-",i4.4,3(":",i2.2))') icd,month(icm),icy,ich,icmi,ics
    call ccnf_put_att(idnc,idnt,'time_origin',timorg)
    write(grdtim,'("minutes since ",i4.4,"-",i2.2,"-",i2.2," ",2(i2.2,":"),i2.2)') icy,icm,icd,ich,icmi,ics
    call ccnf_put_att(idnc,idnt,'units',grdtim)
    if ( leap==0 ) then
      call ccnf_put_att(idnc,idnt,'calendar','noleap')
    end if
    if ( myid==0 ) then
      write(6,*) 'timorg=',timorg
      write(6,*) 'grdtim=',grdtim
    end if

!   create the attributes of the header record of the file
    nahead(1) = il_g       ! needed by cc2hist
    nahead(2) = jl_g       ! needed by cc2hist
    nahead(3) = kl         ! needed by cc2hist
    nahead(4) = 5
    nahead(5) = 0          ! nsd not used now
    nahead(6) = io_in
    nahead(7) = nbd
    nahead(8) = 0          ! not needed now  
    nahead(9) = mex
    nahead(10) = mup
    nahead(11) = 2 ! nem
    nahead(12) = mtimer
    nahead(13) = 0         ! nmi
    nahead(14) = nint(dt)  ! needed by cc2hist
    nahead(15) = 0         ! not needed now 
    nahead(16) = nhor
    nahead(17) = nkuo
    nahead(18) = khdif
    nahead(19) = kl        ! needed by cc2hist (was kwt)
    nahead(20) = 0  !iaa
    nahead(21) = 0  !jaa
    nahead(22) = -4
    nahead(23) = 0  ! not needed now      
    nahead(24) = 0  !lbd
    nahead(25) = nrun
    nahead(26) = 0
    nahead(27) = khor
    nahead(28) = ksc
    nahead(29) = kountr
    nahead(30) = 1 ! ndiur
    nahead(31) = 0  ! spare
    nahead(32) = nhorps
    nahead(33) = nsoil
    nahead(34) = ms        ! needed by cc2hist
    nahead(35) = ntsur
    nahead(36) = nrad
    nahead(37) = kuocb
    nahead(38) = nvmix
    nahead(39) = ntsea
    nahead(40) = 0    
    nahead(41) = nextout
    nahead(42) = ilt
    nahead(43) = ntrac     ! needed by cc2hist
    nahead(44) = nsib
    nahead(45) = nrungcm
    nahead(46) = ncvmix
    nahead(47) = ngwd
    nahead(48) = lgwd
    nahead(49) = mup
    nahead(50) = nritch_t
    nahead(51) = ldr
    nahead(52) = nevapls
    nahead(53) = nevapcc
    nahead(54) = nt_adv
    ahead(1) = ds
    ahead(2) = 0.  !difknbd
    ahead(3) = 0.  ! was rhkuo for kuo scheme
    ahead(4) = 0.  !du
    ahead(5) = rlong0     ! needed by cc2hist
    ahead(6) = rlat0      ! needed by cc2hist
    ahead(7) = schmidt    ! needed by cc2hist
    ahead(8) = 0.  !stl2
    ahead(9) = 0.  !relaxt
    ahead(10) = 0.  !hourbd
    ahead(11) = tss_sh
    ahead(12) = vmodmin
    ahead(13) = av_vmod
    ahead(14) = epsp
    if ( myid==0 ) then
      write(6,*) "nahead=",nahead
      write(6,*) "ahead=",ahead
    end if
    call ccnf_put_attg(idnc,'int_header',nahead)   ! to be depreciated
    call ccnf_put_attg(idnc,'real_header',ahead)   ! to be depreciated
    call ccnf_put_attg(idnc,'date_header',rundate) ! to be depreciated
    call ccnf_def_var(idnc,'ds','float',idv)
    call ccnf_def_var(idnc,'dt','float',idv)

    ! Define global grid
    call ccnf_put_attg(idnc,'dt',dt)
    call ccnf_put_attg(idnc,'il_g',il_g)
    call ccnf_put_attg(idnc,'jl_g',jl_g)
    call ccnf_put_attg(idnc,'rlat0',rlat0)
    call ccnf_put_attg(idnc,'rlong0',rlong0)
    call ccnf_put_attg(idnc,'schmidt',schmidt)
    call ccnf_put_attg(idnc,'ms',ms)
    call ccnf_put_attg(idnc,'ntrac',ntrac)
    
    ! store CCAM parameters
    call ccnf_put_attg(idnc,'aeroindir',aeroindir)
    call ccnf_put_attg(idnc,'alphaj',alphaj)
    if (amipo3) then
      namipo3=1
    else
      namipo3=0
    end if
    call ccnf_put_attg(idnc,'amipo3',namipo3)
    call ccnf_put_attg(idnc,'av_vmod',av_vmod)
    call ccnf_put_attg(idnc,'bpyear',bpyear)
    call ccnf_put_attg(idnc,'ccycle',ccycle)
    call ccnf_put_attg(idnc,'cgmap_offset',cgmap_offset)
    call ccnf_put_attg(idnc,'cgmap_scale',cgmap_scale)
    call ccnf_put_attg(idnc,'ch_dust',ch_dust)
    call ccnf_put_attg(idnc,'charnock',charnock)
    call ccnf_put_attg(idnc,'chn10',chn10)
    call ccnf_put_attg(idnc,'epsf',epsf)
    call ccnf_put_attg(idnc,'epsh',epsh)
    call ccnf_put_attg(idnc,'epsp',epsp)
    call ccnf_put_attg(idnc,'epsu',epsu)
    call ccnf_put_attg(idnc,'factchseaice',factchseaice)
    call ccnf_put_attg(idnc,'fc2',fc2)
    call ccnf_put_attg(idnc,'helim',helim)
    call ccnf_put_attg(idnc,'helmmeth',helmmeth)
    call ccnf_put_attg(idnc,'iaero',iaero)   
    call ccnf_put_attg(idnc,'iceradmethod',iceradmethod)   
    call ccnf_put_attg(idnc,'jalbfix',jalbfix)
    call ccnf_put_attg(idnc,'kblock',kblock)
    call ccnf_put_attg(idnc,'kbotdav',kbotdav)
    call ccnf_put_attg(idnc,'kbotmlo',kbotmlo)
    call ccnf_put_attg(idnc,'khdif',khdif)
    call ccnf_put_attg(idnc,'khor',khor)
    call ccnf_put_attg(idnc,'knh',knh)
    call ccnf_put_attg(idnc,'ktopdav',ktopdav)
    call ccnf_put_attg(idnc,'ktopmlo',ktopmlo)
    call ccnf_put_attg(idnc,'leap',leap)
    call ccnf_put_attg(idnc,'liqradmethod',liqradmethod)    
    call ccnf_put_attg(idnc,'lgwd',lgwd)
    call ccnf_put_attg(idnc,'m_fly',m_fly)
    call ccnf_put_attg(idnc,'mbd',mbd)
    call ccnf_put_attg(idnc,'mbd_maxgrid',mbd_maxgrid)
    call ccnf_put_attg(idnc,'mbd_maxscale',mbd_maxscale)
    call ccnf_put_attg(idnc,'mex',mex)
    call ccnf_put_attg(idnc,'mfix',mfix)
    call ccnf_put_attg(idnc,'mfix_aero',mfix_aero)
    call ccnf_put_attg(idnc,'mfix_qg',mfix_qg)
    call ccnf_put_attg(idnc,'mfix_tr',mfix_tr)
    call ccnf_put_attg(idnc,'mh_bs',mh_bs)
    call ccnf_put_attg(idnc,'mindep',mindep)
    call ccnf_put_attg(idnc,'minwater',minwater)
    call ccnf_put_attg(idnc,'mloalpha',mloalpha)
    call ccnf_put_attg(idnc,'mlodiff',mlodiff)
    call ccnf_put_attg(idnc,'mup',mup)
    call ccnf_put_attg(idnc,'mxd',mxd)
    call ccnf_put_attg(idnc,'nalpha',nalpha)
    call ccnf_put_attg(idnc,'namip',namip)
    call ccnf_put_attg(idnc,'nbarewet',nbarewet)
    call ccnf_put_attg(idnc,'nbd',nbd)
    call ccnf_put_attg(idnc,'newrough',newrough)
    call ccnf_put_attg(idnc,'newtop',newtop)
    call ccnf_put_attg(idnc,'newztsea',newztsea)
    call ccnf_put_attg(idnc,'nglacier',nglacier)
    call ccnf_put_attg(idnc,'ngwd',ngwd)
    call ccnf_put_attg(idnc,'nh',nh)
    call ccnf_put_attg(idnc,'nhor',nhor)
    call ccnf_put_attg(idnc,'nhorjlm',nhorjlm)
    call ccnf_put_attg(idnc,'nhorps',nhorps)
    call ccnf_put_attg(idnc,'nhstest',nhstest)
    call ccnf_put_attg(idnc,'nlocal',nlocal)
    call ccnf_put_attg(idnc,'nmlo',nmlo)
    call ccnf_put_attg(idnc,'nmr',nmr)
    call ccnf_put_attg(idnc,'nplens',nplens)
    call ccnf_put_attg(idnc,'nrad',nrad)
    call ccnf_put_attg(idnc,'nritch_t',nritch_t)
    call ccnf_put_attg(idnc,'nriver',nriver)
    call ccnf_put_attg(idnc,'nsemble',nsemble)
    call ccnf_put_attg(idnc,'nsib',nsib)
    call ccnf_put_attg(idnc,'nsigmf',nsigmf)
    call ccnf_put_attg(idnc,'nspecial',nspecial)
    call ccnf_put_attg(idnc,'nstagu',nstagu)
    call ccnf_put_attg(idnc,'nt_adv',nt_adv)
    call ccnf_put_attg(idnc,'ntaft',ntaft)
    call ccnf_put_attg(idnc,'ntbar',ntbar)
    call ccnf_put_attg(idnc,'ntsea',ntsea)
    call ccnf_put_attg(idnc,'ntsur',ntsur)
    call ccnf_put_attg(idnc,'nud_hrs',nud_hrs)
    call ccnf_put_attg(idnc,'nud_ouv',nud_ouv)
    call ccnf_put_attg(idnc,'nud_p',nud_p)
    call ccnf_put_attg(idnc,'nud_q',nud_q)
    call ccnf_put_attg(idnc,'nud_sfh',nud_sfh)
    call ccnf_put_attg(idnc,'nud_sss',nud_sss)    
    call ccnf_put_attg(idnc,'nud_sst',nud_sst)
    call ccnf_put_attg(idnc,'nud_t',nud_t)
    call ccnf_put_attg(idnc,'nud_uv',nud_uv)
    call ccnf_put_attg(idnc,'nudu_hrs',nudu_hrs)
    call ccnf_put_attg(idnc,'nurban',nurban)
    call ccnf_put_attg(idnc,'nvmix',nvmix)
    call ccnf_put_attg(idnc,'ocneps',ocneps)
    call ccnf_put_attg(idnc,'ocnsmag',ocnsmag)
    call ccnf_put_attg(idnc,'ol',ol)
    call ccnf_put_attg(idnc,'panfg',panfg)
    call ccnf_put_attg(idnc,'panzo',panzo)
    call ccnf_put_attg(idnc,'precon',precon)
    call ccnf_put_attg(idnc,'proglai',proglai)
    call ccnf_put_attg(idnc,'qgmin',qgmin)
    call ccnf_put_attg(idnc,'rescrn',rescrn)
    call ccnf_put_attg(idnc,'restol',restol)
    call ccnf_put_attg(idnc,'rhsat',rhsat)
    call ccnf_put_attg(idnc,'sigbot_gwd',sigbot_gwd)
    call ccnf_put_attg(idnc,'sigramphigh',sigramphigh)
    call ccnf_put_attg(idnc,'sigramplow',sigramplow)
    call ccnf_put_attg(idnc,'snmin',snmin)
    call ccnf_put_attg(idnc,'tbave',tbave)
    call ccnf_put_attg(idnc,'tblock',tblock)
    call ccnf_put_attg(idnc,'tss_sh',tss_sh)
    call ccnf_put_attg(idnc,'usetide',usetide)
    call ccnf_put_attg(idnc,'vmodmin',vmodmin)
    call ccnf_put_attg(idnc,'zobgin',zobgin)
    call ccnf_put_attg(idnc,'zomode',zomode)
    call ccnf_put_attg(idnc,'zoseaice',zoseaice)
    call ccnf_put_attg(idnc,'zvolcemi',zvolcemi)

    call ccnf_put_attg(idnc,'mins_rad',mins_rad)
    call ccnf_put_attg(idnc,'sw_diff_streams',sw_diff_streams)
    call ccnf_put_attg(idnc,'sw_resolution',sw_resolution)
    
    call ccnf_put_attg(idnc,'acon',acon)
    call ccnf_put_attg(idnc,'alflnd',alflnd)
    call ccnf_put_attg(idnc,'alfsea',alfsea)
    call ccnf_put_attg(idnc,'bcon',bcon)
    call ccnf_put_attg(idnc,'convfact',convfact)
    call ccnf_put_attg(idnc,'convtime',convtime)
    call ccnf_put_attg(idnc,'detrain',detrain)
    call ccnf_put_attg(idnc,'dsig2',dsig2)
    call ccnf_put_attg(idnc,'entrain',entrain)
    call ccnf_put_attg(idnc,'fldown',fldown)
    call ccnf_put_attg(idnc,'iterconv',iterconv)
    call ccnf_put_attg(idnc,'ksc',ksc)
    call ccnf_put_attg(idnc,'kscmom',kscmom)
    call ccnf_put_attg(idnc,'kscsea',kscsea)
    call ccnf_put_attg(idnc,'ldr',ldr)
    call ccnf_put_attg(idnc,'mbase',mbase)
    call ccnf_put_attg(idnc,'mdelay',mdelay)
    call ccnf_put_attg(idnc,'methdetr',methdetr)
    call ccnf_put_attg(idnc,'methprec',methprec)
    call ccnf_put_attg(idnc,'nbase',nbase)
    call ccnf_put_attg(idnc,'ncldia',nclddia)
    call ccnf_put_attg(idnc,'ncloud',ncloud)
    call ccnf_put_attg(idnc,'ncvcloud',ncvcloud)
    call ccnf_put_attg(idnc,'nevapcc',nevapcc)
    call ccnf_put_attg(idnc,'nevapls',nevapls)
    call ccnf_put_attg(idnc,'nkuo',nkuo)
    call ccnf_put_attg(idnc,'nuvconv',nuvconv)
    call ccnf_put_attg(idnc,'rhcv',rhcv)
    call ccnf_put_attg(idnc,'tied_con',tied_con)
    call ccnf_put_attg(idnc,'tied_over',tied_over)

    call ccnf_put_attg(idnc,'b1',b1)
    call ccnf_put_attg(idnc,'b2',b2)
    call ccnf_put_attg(idnc,'be',be)
    call ccnf_put_attg(idnc,'buoymeth',buoymeth)
    call ccnf_put_attg(idnc,'ce0',ce0)
    call ccnf_put_attg(idnc,'ce1',ce1)
    call ccnf_put_attg(idnc,'ce2',ce2)
    call ccnf_put_attg(idnc,'ce3',ce3)
    call ccnf_put_attg(idnc,'cm0',cm0)
    call ccnf_put_attg(idnc,'cq',cq)
    call ccnf_put_attg(idnc,'drrc0',dtrc0)
    call ccnf_put_attg(idnc,'dtrn0',dtrn0)
    call ccnf_put_attg(idnc,'ent0',ent0)
    call ccnf_put_attg(idnc,'icm1',icm1)
    call ccnf_put_attg(idnc,'m0',m0)
    call ccnf_put_attg(idnc,'maxdts',maxdts)
    call ccnf_put_attg(idnc,'maxl',maxl)
    call ccnf_put_attg(idnc,'mineps',mineps)
    call ccnf_put_attg(idnc,'minl',minl)
    call ccnf_put_attg(idnc,'mintke',mintke)
    call ccnf_put_attg(idnc,'stabmeth',stabmeth)

  else
    if ( myid==0 ) write(6,'(" outcdf itype,idnc,iarch,cdffile=",i5,i8,i5," ",a80)') itype,idnc,iarch,cdffile
  endif ! ( iarch=1 ) ..else..
endif ! (myid==0.or.localhist)
      
! openhist writes some fields so needs to be called by all processes
call openhist(iarch,itype,dima,localhist,idnc,nstagin,ixp,iyp,idlev,idms,idoc)

if ( myid==0 .or. localhist ) then
  if ( ktau==ntau ) then
    if ( myid==0 ) write(6,*) "closing netCDF file idnc=",idnc      
    call ccnf_close(idnc)
  endif
endif    ! (myid==0.or.local)

return
end subroutine cdfout
      
!--------------------------------------------------------------
! CREATE ATTRIBUTES AND WRITE OUTPUT
subroutine openhist(iarch,itype,idim,local,idnc,nstagin,ixp,iyp,idlev,idms,idoc)

use aerointerface                                ! Aerosol interface
use aerosolldr                                   ! LDR prognostic aerosols
use arrays_m                                     ! Atmosphere dyamics prognostic arrays
use ateb, only : atebsave, urbtemp               ! Urban
use cable_ccam, only : savetile, savetiledef     ! CABLE interface
use cable_def_types_mod, only : ncs, ncp         ! CABLE dimensions
use casadimension, only : mplant, mlitter, msoil ! CASA dimensions
use carbpools_m                                  ! Carbon pools
use cc_mpi                                       ! CC MPI routines
use cfrac_m                                      ! Cloud fraction
use cloudmod                                     ! Prognostic strat cloud
use daviesnudge                                  ! Far-field nudging
use dpsdt_m                                      ! Vertical velocity
use extraout_m                                   ! Additional diagnostics
use gdrag_m                                      ! Gravity wave drag
use histave_m                                    ! Time average arrays
use infile                                       ! Input file routines
use latlong_m                                    ! Lat/lon coordinates
use liqwpar_m                                    ! Cloud water mixing ratios
use map_m                                        ! Grid map arrays
use mlo, only : wlev,mlosave,mlodiag, &          ! Ocean physics and prognostic arrays
                mloexpdep,wrtemp
use mlodynamics                                  ! Ocean dynamics
use mlodynamicsarrays_m                          ! Ocean dynamics data
use morepbl_m                                    ! Additional boundary layer diagnostics
use nharrs_m                                     ! Non-hydrostatic atmosphere arrays
use nsibd_m                                      ! Land-surface arrays
use pbl_m                                        ! Boundary layer arrays
use prec_m                                       ! Precipitation
use raddiag_m                                    ! Radiation diagnostic
use riverarrays_m                                ! River data
use savuvt_m                                     ! Saved dynamic arrays
use savuv1_m                                     ! Saved dynamic arrays
use screen_m                                     ! Screen level diagnostics
use sigs_m                                       ! Atmosphere sigma levels
use soil_m                                       ! Soil and surface data
use soilsnow_m                                   ! Soil, snow and surface data
use tkeeps, only : tke,eps,zidry                 ! TKE-EPS boundary layer
use tracermodule, only : writetrpm               ! Tracer routines
use tracers_m                                    ! Tracer data
use vegpar_m                                     ! Vegetation arrays
use vvel_m                                       ! Additional vertical velocity
use work2_m                                      ! Diagnostic arrays
use xarrs_m, only : pslx                         ! Saved dynamic arrays

implicit none

include 'newmpar.h'                              ! Grid parameters
include 'const_phys.h'                           ! Physical constants
include 'dates.h'                                ! Date data
include 'filnames.h'                             ! Filenames
include 'kuocom.h'                               ! Convection parameters
include 'parm.h'                                 ! Model configuration
include 'parmdyn.h'                              ! Dynamics parameters
include 'soilv.h'                                ! Soil parameters
include 'version.h'                              ! Model version data

integer ixp,iyp,idlev,idms,idoc
integer i, idkdate, idktau, idktime, idmtimer, idnteg, idnter
integer idv, iq, j, k, n, igas, idnc
integer iarch, itype, nstagin, idum
integer, dimension(4), intent(in) :: idim
integer, dimension(3) :: jdim
real, dimension(ms) :: zsoil
real, dimension(il_g) :: xpnt
real, dimension(jl_g) :: ypnt
real, dimension(ifull) :: aa
real, dimension(ifull) :: ocndep,ocnheight
real, dimension(ifull) :: qtot, tv
real, dimension(ifull,kl) :: tmpry,rhoa
real, dimension(ifull,wlev,4) :: mlodwn
real, dimension(ifull,11) :: micdwn
real, dimension(ifull,32) :: atebdwn
character(len=50) expdesc
character(len=50) lname
character(len=21) mnam,nnam
character(len=8) vname
character(len=3) trnum
logical, intent(in) :: local
logical lwrite,lave,lrad,lday
logical l3hr

! flags to control output
lwrite = ktau>0
lave = mod(ktau,nperavg)==0.or.ktau==ntau
lave = lave.and.ktau>0
lrad = mod(ktau,kountr)==0.or.ktau==ntau
lrad = lrad.and.ktau>0
lday = mod(ktau,nperday)==0
lday = lday.and.ktau>0
l3hr = (real(nwt)*dt>10800.)

! idim is for 4-D (3 dimensions+time)
! jdim is for 3-D (2 dimensions+time)
jdim(1:2) = idim(1:2)
jdim(3)   = idim(4)

if( myid==0 .or. local ) then

! if this is the first archive, set up some global attributes
  if ( iarch==1 ) then

!   Create global attributes
!   Model run number
    if ( myid==0 ) then
      write(6,*) 'idim=',idim
      write(6,*) 'nrun=',nrun
    end if
    call ccnf_put_attg(idnc,'nrun',nrun)

!   Experiment description
    expdesc = 'CCAM model run'
    call ccnf_put_attg(idnc,'expdesc',expdesc)

!   Model version
    call ccnf_put_attg(idnc,'version',version)

    if ( local ) then
      call ccnf_put_attg(idnc,'processor_num',myid)
      call ccnf_put_attg(idnc,'nproc',nproc)
#ifdef uniform_decomp
      call ccnf_put_attg(idnc,'decomp','uniform1')
#else
      call ccnf_put_attg(idnc,'decomp','face')
#endif
    endif           

!       Sigma levels
    if ( myid==0 ) write(6,*) 'sig=',sig
    call ccnf_put_attg(idnc,'sigma',sig)

    lname = 'year-month-day at start of run'
    call ccnf_def_var(idnc,'kdate','int',1,idim(4:4),idkdate)
    call ccnf_put_att(idnc,idkdate,'long_name',lname)

    lname = 'hour-minute at start of run'
    call ccnf_def_var(idnc,'ktime','int',1,idim(4:4),idktime)
    call ccnf_put_att(idnc,idktime,'long_name',lname)

    lname = 'timer (hrs)'
    call ccnf_def_var(idnc,'timer','float',1,idim(4:4),idnter)
    call ccnf_put_att(idnc,idnter,'long_name',lname)

    lname = 'mtimer (mins)'
    call ccnf_def_var(idnc,'mtimer','int',1,idim(4:4),idmtimer)
    call ccnf_put_att(idnc,idmtimer,'long_name',lname)

    lname = 'timeg (UTC)'
    call ccnf_def_var(idnc,'timeg','float',1,idim(4:4),idnteg)
    call ccnf_put_att(idnc,idnteg,'long_name',lname)

    lname = 'number of time steps from start'
    call ccnf_def_var(idnc,'ktau','int',1,idim(4:4),idktau)
    call ccnf_put_att(idnc,idktau,'long_name',lname)

    lname = 'down'
    call ccnf_def_var(idnc,'sigma','float',1,idim(3:3),idv)
    call ccnf_put_att(idnc,idv,'positive',lname)

    lname = 'atm stag direction'
    call ccnf_def_var(idnc,'nstag','int',1,idim(4:4),idv)
    call ccnf_put_att(idnc,idv,'long_name',lname)

    lname = 'atm unstag direction'
    call ccnf_def_var(idnc,'nstagu','int',1,idim(4:4),idv)
    call ccnf_put_att(idnc,idv,'long_name',lname)

    lname = 'atm stag offset'
    call ccnf_def_var(idnc,'nstagoff','int',1,idim(4:4),idv)
    call ccnf_put_att(idnc,idv,'long_name',lname)

    if ( (nmlo<0.and.nmlo>=-9) .or. (nmlo>0.and.nmlo<=9.and.itype==-1) ) then
      lname = 'ocn stag offset'
      call ccnf_def_var(idnc,'nstagoffmlo','int',1,idim(4:4),idv)
      call ccnf_put_att(idnc,idv,'long_name',lname)     
    end if

    if ( myid==0 ) write(6,*) 'define attributes of variables'

!   For time invariant surface fields
    lname = 'Surface geopotential'
    call attrib(idnc,idim(1:2),2,'zht',lname,'m2/s2',-1000.,90.e3,0,-1)
    lname = 'Std Dev of surface height'
    call attrib(idnc,idim(1:2),2,'he',lname,'m',0.,90.e3,0,-1)
    lname = 'Map factor'
    call attrib(idnc,idim(1:2),2,'map',lname,'none',.001,1500.,0,itype)
    lname = 'Coriolis factor'
    call attrib(idnc,idim(1:2),2,'cor',lname,'1/sec',-1.5e-4,1.5e-4,0,itype)
    lname = 'Urban fraction'
    call attrib(idnc,idim(1:2),2,'sigmu',lname,'none',0.,3.25,0,itype)
    lname = 'Soil type'
    call attrib(idnc,idim(1:2),2,'soilt',lname,'none',-65.,65.,0,itype)
    lname = 'Vegetation type'
    call attrib(idnc,idim(1:2),2,'vegt',lname,'none',0.,65.,0,itype)

    if ( (nmlo<0.and.nmlo>=-9) .or. (nmlo>0.and.nmlo<=9.and.itype==-1) ) then
      lname = 'Water bathymetry'
      call attrib(idnc,idim(1:2),2,'ocndepth',lname,'m',0.,32500.,0,itype)
    end if

!   For time varying surface fields
    if ( nsib==6 .or. nsib==7 ) then
      lname = 'Stomatal resistance'
      call attrib(idnc,jdim(1:3),3,'rs',lname,'none',0.,1000.,0,itype)
    else
      lname = 'Minimum stomatal resistance'
      call attrib(idnc,idim(1:2),2,'rsmin',lname,'none',0.,1000.,0,itype)
    end if
    lname = 'Vegetation fraction'
    call attrib(idnc,jdim(1:3),3,'sigmf',lname,'none',0.,3.25,0,itype)
    lname ='Scaled Log Surface pressure'
    call attrib(idnc,jdim(1:3),3,'psf',lname,'none',-1.3,0.2,0,itype)
    lname ='Mean sea level pressure'
    call attrib(idnc,jdim(1:3),3,'pmsl',lname,'hPa',800.,1200.,0,itype)
    lname = 'Surface roughness'
    call attrib(idnc,jdim(1:3),3,'zolnd',lname,'m',0.,65.,0,-1) ! -1=long
    lname = 'Leaf area index'
    call attrib(idnc,jdim(1:3),3,'lai',lname,'none',0.,32.5,0,itype)
    lname = 'Surface temperature'
    call attrib(idnc,jdim(1:3),3,'tsu',lname,'K',100.,425.,0,itype)
    lname = 'Pan temperature'
    call attrib(idnc,jdim(1:3),3,'tpan',lname,'K',100.,425.,0,itype)
    lname = 'Precipitation'
    call attrib(idnc,jdim(1:3),3,'rnd',lname,'mm/day',0.,1300.,0,-1)  ! -1=long
    lname = 'Convective precipitation'
    call attrib(idnc,jdim(1:3),3,'rnc',lname,'mm/day',0.,1300.,0,-1)  ! -1=long
    lname = 'Snowfall'
    call attrib(idnc,jdim(1:3),3,'sno',lname,'mm/day',0.,1300.,0,-1)  ! -1=long
    lname = 'Graupelfall'
    call attrib(idnc,jdim(1:3),3,'grpl',lname,'mm/day',0.,1300.,0,-1) ! -1=long    
    lname = 'Runoff'
    call attrib(idnc,jdim(1:3),3,'runoff',lname,'mm/day',0.,1300.,0,-1) ! -1=long
    lname = 'Surface albedo'
    call attrib(idnc,jdim(1:3),3,'alb',lname,'none',0.,1.,0,itype)
    lname = 'Fraction of canopy that is wet'
    call attrib(idnc,jdim(1:3),3,'fwet',lname,'none',0.,1.,0,itype)

    lname = 'Snow depth (liquid water)'
    call attrib(idnc,jdim(1:3),3,'snd',lname,'mm',0.,6500.,0,-1)  ! -1=long
    lname = 'Soil temperature lev 1'
    call attrib(idnc,jdim(1:3),3,'tgg1',lname,'K',100.,425.,0,itype)
    lname = 'Soil temperature lev 2'
    call attrib(idnc,jdim(1:3),3,'tgg2',lname,'K',100.,425.,0,itype)
    lname = 'Soil temperature lev 3'
    call attrib(idnc,jdim(1:3),3,'tgg3',lname,'K',100.,425.,0,itype)
    lname = 'Soil temperature lev 4'
    call attrib(idnc,jdim(1:3),3,'tgg4',lname,'K',100.,425.,0,itype)
    lname = 'Soil temperature lev 5'
    call attrib(idnc,jdim(1:3),3,'tgg5',lname,'K',100.,425.,0,itype)
    lname = 'Soil temperature lev 6'
    call attrib(idnc,jdim(1:3),3,'tgg6',lname,'K',100.,425.,0,itype)
 
    if ( (nmlo<0.and.nmlo>=-9) .or. (nmlo>0.and.nmlo<=9.and.itype==-1) ) then
      do k=ms+1,wlev
        write(lname,'("soil/ocean temperature lev ",I2)') k
        write(vname,'("tgg",I2.2)') k
        call attrib(idnc,jdim(1:3),3,vname,lname,'K',100.,425.,0,itype)
      end do
      do k=1,wlev
        write(lname,'("ocean salinity lev ",I2)') k
        write(vname,'("sal",I2.2)') k
        call attrib(idnc,jdim(1:3),3,vname,lname,'PSU',0.,130.,0,itype)
      end do
      do k=1,wlev
        write(lname,'("x-component current lev ",I2)') k
        write(vname,'("uoc",I2.2)') k
        call attrib(idnc,jdim(1:3),3,vname,lname,'m/s',-65.,65.,0,itype)
        write(lname,'("y-component current lev ",I2)') k
        write(vname,'("voc",I2.2)') k
        call attrib(idnc,jdim(1:3),3,vname,lname,'m/s',-65.,65.,0,itype)
      end do
      lname = 'water surface height'
      call attrib(idnc,jdim(1:3),3,'ocheight',lname,'m',-130.,130.,0,itype)          
      lname = 'Snow temperature lev 1'
      call attrib(idnc,jdim(1:3),3,'tggsn1',lname,'K',100.,425.,0,itype)
      lname = 'Snow temperature lev 2'
      call attrib(idnc,jdim(1:3),3,'tggsn2',lname,'K',100.,425.,0,itype)
      lname = 'Snow temperature lev 3'
      call attrib(idnc,jdim(1:3),3,'tggsn3',lname,'K',100.,425.,0,itype)
      lname = 'Ice temperature lev 4'
      call attrib(idnc,jdim(1:3),3,'tggsn4',lname,'K',100.,425.,0,itype)
      lname = 'Ice heat store'
      call attrib(idnc,jdim(1:3),3,'sto',lname,'J/m2',0.,1.3e10,0,itype)
      lname = 'x-component ice velocity'
      call attrib(idnc,jdim(1:3),3,'uic',lname,'m/s',-65.,65.,0,itype)
      lname = 'y-component ice velocity'
      call attrib(idnc,jdim(1:3),3,'vic',lname,'m/s',-65.,65.,0,itype)
      lname = 'Ice salinity'
      call attrib(idnc,jdim(1:3),3,'icesal',lname,'PSU',0.,130.,0,itype)
    end if
    if ( nmlo<=-2 .or. (nmlo>=2.and.itype==-1) .or. nriver==1 ) then
      lname = 'Surface water depth'
      call attrib(idnc,jdim(1:3),3,'swater',lname,'mm',0.,6.5E3,0,-1) ! -1 = long
    end if

    lname = 'Wetness fraction layer 1' ! 5. for frozen sand
    call attrib(idnc,jdim(1:3),3,'wetfrac1',lname,'none',-6.5,6.5,0,itype)
    lname = 'Wetness fraction layer 2'
    call attrib(idnc,jdim(1:3),3,'wetfrac2',lname,'none',-6.5,6.5,0,itype)
    lname = 'Wetness fraction layer 3'
    call attrib(idnc,jdim(1:3),3,'wetfrac3',lname,'none',-6.5,6.5,0,itype)
    lname = 'Wetness fraction layer 4'
    call attrib(idnc,jdim(1:3),3,'wetfrac4',lname,'none',-6.5,6.5,0,itype)
    lname = 'Wetness fraction layer 5'
    call attrib(idnc,jdim(1:3),3,'wetfrac5',lname,'none',-6.5,6.5,0,itype)
    lname = 'Wetness fraction layer 6'
    call attrib(idnc,jdim(1:3),3,'wetfrac6',lname,'none',-6.5,6.5,0,itype)
     
    ! PH - Add wetfac to output for mbase=-19 option
    lname = 'Surface wetness fraction'
    call attrib(idnc,jdim(1:3),3,'wetfac',lname,'none',-6.5,6.5,0,itype)

    lname = 'Sea ice depth'
    call attrib(idnc,jdim(1:3),3,'siced',lname,'m',0.,65.,0,-1)
    lname = 'Sea ice fraction'
    call attrib(idnc,jdim(1:3),3,'fracice',lname,'none',0.,6.5,0,itype)
    lname = '10m wind speed'
    call attrib(idnc,jdim(1:3),3,'u10',lname,'m/s',0.,130.,0,itype)
    lname = 'Maximum CAPE'
    call attrib(idnc,jdim(1:3),3,'cape_max',lname,'J/kg',0.,20000.,0,itype)
    lname = 'Average CAPE'
    call attrib(idnc,jdim(1:3),3,'cape_ave',lname,'J/kg',0.,20000.,0,itype)    
    
    lname = 'Maximum precip rate in a timestep'
    call attrib(idnc,jdim(1:3),3,'maxrnd',lname,'mm/day',0.,2600.,1,-1) ! -1=long
    lname = 'Maximum screen temperature'
    call attrib(idnc,jdim(1:3),3,'tmaxscr',lname,'K',100.,425.,1,itype)
    lname = 'Minimum screen temperature'
    call attrib(idnc,jdim(1:3),3,'tminscr',lname,'K',100.,425.,1,itype)
    lname = 'Maximum screen relative humidity'
    call attrib(idnc,jdim(1:3),3,'rhmaxscr',lname,'%',0.,200.,1,itype)
    lname = 'Minimum screen relative humidity'
    call attrib(idnc,jdim(1:3),3,'rhminscr',lname,'%',0.,200.,1,itype)
    lname = 'x-component max 10m wind'
    call attrib(idnc,jdim(1:3),3,'u10max',lname,'m/s',-99.,99.,1,itype)
    lname = 'y-component max 10m wind'
    call attrib(idnc,jdim(1:3),3,'v10max',lname,'m/s',-99.,99.,1,itype)
    lname = 'Maximum 10m wind speed'
    call attrib(idnc,jdim(1:3),3,'sfcwindmax',lname,'m/s',0.,199.,1,itype)
    lname = 'x-component max level_1 wind'
    call attrib(idnc,jdim(1:3),3,'u1max',lname,'m/s',-99.,99.,1,itype)
    lname = 'y-component max level_1 wind'
    call attrib(idnc,jdim(1:3),3,'v1max',lname,'m/s',-99.,99.,1,itype)
    lname = 'x-component max level_2 wind'
    call attrib(idnc,jdim(1:3),3,'u2max',lname,'m/s',-99.,99.,1,itype)
    lname = 'y-component max level_2 wind'
    call attrib(idnc,jdim(1:3),3,'v2max',lname,'m/s',-99.,99.,1,itype)
    if ( l3hr ) then
      lname = '3hr precipitation'
      call attrib(idnc,jdim(1:3),3,'rnd03',lname,'mm',0.,1300.,1,itype)
      lname = '6hr precipitation'
      call attrib(idnc,jdim(1:3),3,'rnd06',lname,'mm',0.,1300.,1,itype)
      lname = '9hr precipitation'
      call attrib(idnc,jdim(1:3),3,'rnd09',lname,'mm',0.,1300.,1,itype)
      lname = '12hr precipitation'
      call attrib(idnc,jdim(1:3),3,'rnd12',lname,'mm',0.,1300.,1,itype)
      lname = '15hr precipitation'
      call attrib(idnc,jdim(1:3),3,'rnd15',lname,'mm',0.,1300.,1,itype)
      lname = '18hr precipitation'
      call attrib(idnc,jdim(1:3),3,'rnd18',lname,'mm',0.,1300.,1,itype)
      lname = '21hr precipitation'
      call attrib(idnc,jdim(1:3),3,'rnd21',lname,'mm',0.,1300.,1,itype)
    end if
    lname = '24hr precipitation'
    call attrib(idnc,jdim(1:3),3,'rnd24',lname,'mm',0.,1300.,1,itype)
    if ( nextout>=2 .and. l3hr ) then  ! 6-hourly u10, v10, tscr, rh1
      mnam ='x-component 10m wind '
      nnam ='y-component 10m wind '
      call attrib(idnc,jdim(1:3),3,'u10_06',mnam//'6hr','m/s',-99.,99.,1,itype)
      call attrib(idnc,jdim(1:3),3,'v10_06',nnam//'6hr','m/s',-99.,99.,1,itype)
      call attrib(idnc,jdim(1:3),3,'u10_12',mnam//'12hr','m/s',-99.,99.,1,itype)
      call attrib(idnc,jdim(1:3),3,'v10_12',nnam//'12hr','m/s',-99.,99.,1,itype)
      call attrib(idnc,jdim(1:3),3,'u10_18',mnam//'18hr','m/s',-99.,99.,1,itype)
      call attrib(idnc,jdim(1:3),3,'v10_18',nnam//'18hr','m/s',-99.,99.,1,itype)
      call attrib(idnc,jdim(1:3),3,'u10_24',mnam//'24hr','m/s',-99.,99.,1,itype)
      call attrib(idnc,jdim(1:3),3,'v10_24',nnam//'24hr','m/s',-99.,99.,1,itype)
      mnam ='tscrn 3-hrly'
      nnam ='rhum level_1 3-hrly'
      call attrib(idnc,jdim(1:3),3,'tscr_06',mnam//'6hr', 'K',100.,425.,1,itype)
      call attrib(idnc,jdim(1:3),3,'tscr_12',mnam//'12hr','K',100.,425.,1,itype)
      call attrib(idnc,jdim(1:3),3,'tscr_18',mnam//'18hr','K',100.,425.,1,itype)
      call attrib(idnc,jdim(1:3),3,'tscr_24',mnam//'24hr','K',100.,425.,1,itype)
      call attrib(idnc,jdim(1:3),3,'rh1_06', nnam//'6hr', '%',-9.,200.,1,itype)
      call attrib(idnc,jdim(1:3),3,'rh1_12', nnam//'12hr','%',-9.,200.,1,itype)
      call attrib(idnc,jdim(1:3),3,'rh1_18', nnam//'18hr','%',-9.,200.,1,itype)
      call attrib(idnc,jdim(1:3),3,'rh1_24', nnam//'24hr','%',-9.,200.,1,itype)
    endif     ! (nextout>=2)
    if ( nextout>=3 .and. l3hr ) then  ! also 3-hourly u10, v10, tscr, rh1
      call attrib(idnc,jdim(1:3),3,'tscr_03',mnam//'3hr', 'K',100.,425.,1,itype)
      call attrib(idnc,jdim(1:3),3,'tscr_09',mnam//'9hr', 'K',100.,425.,1,itype)
      call attrib(idnc,jdim(1:3),3,'tscr_15',mnam//'15hr','K',100.,425.,1,itype)
      call attrib(idnc,jdim(1:3),3,'tscr_21',mnam//'21hr','K',100.,425.,1,itype)
      call attrib(idnc,jdim(1:3),3,'rh1_03', nnam//'3hr', '%',-9.,200.,1,itype)
      call attrib(idnc,jdim(1:3),3,'rh1_09', nnam//'9hr', '%',-9.,200.,1,itype)
      call attrib(idnc,jdim(1:3),3,'rh1_15', nnam//'15hr','%',-9.,200.,1,itype)
      call attrib(idnc,jdim(1:3),3,'rh1_21', nnam//'21hr','%',-9.,200.,1,itype)
      mnam ='x-component 10m wind '
      nnam ='y-component 10m wind '
      call attrib(idnc,jdim(1:3),3,'u10_03',mnam//'3hr','m/s',-99.,99.,1,itype)
      call attrib(idnc,jdim(1:3),3,'v10_03',nnam//'3hr','m/s',-99.,99.,1,itype)
      call attrib(idnc,jdim(1:3),3,'u10_09',mnam//'9hr','m/s',-99.,99.,1,itype)
      call attrib(idnc,jdim(1:3),3,'v10_09',nnam//'9hr','m/s',-99.,99.,1,itype)
      call attrib(idnc,jdim(1:3),3,'u10_15',mnam//'15hr','m/s',-99.,99.,1,itype)
      call attrib(idnc,jdim(1:3),3,'v10_15',nnam//'15hr','m/s',-99.,99.,1,itype)
      call attrib(idnc,jdim(1:3),3,'u10_21',mnam//'21hr','m/s',-99.,99.,1,itype)
      call attrib(idnc,jdim(1:3),3,'v10_21',nnam//'21hr','m/s',-99.,99.,1,itype)
    endif     ! (nextout>=3)

    lname = 'Average screen temperature'
    call attrib(idnc,jdim(1:3),3,'tscr_ave',lname,'K',100.,425.,0,itype)
    lname = 'Avg cloud base'
    call attrib(idnc,jdim(1:3),3,'cbas_ave',lname,'sigma',0.,1.1,0,itype)
    lname = 'Avg cloud top'
    call attrib(idnc,jdim(1:3),3,'ctop_ave',lname,'sigma',0.,1.1,0,itype)
    lname = 'Avg dew flux'
    call attrib(idnc,jdim(1:3),3,'dew_ave',lname,'W/m2',-100.,1000.,0,itype)
    lname = 'Avg evaporation'
    call attrib(idnc,jdim(1:3),3,'evap',lname,'mm',-100.,100.,0,itype)
    lname = 'Avg potential "pan" evaporation'
    call attrib(idnc,jdim(1:3),3,'epan_ave',lname,'W/m2',-1000.,10.e3,0,itype)
    lname = 'Avg potential evaporation'
    call attrib(idnc,jdim(1:3),3,'epot_ave',lname,'W/m2',-1000.,10.e3,0,itype)
    lname = 'Avg latent heat flux'
    call attrib(idnc,jdim(1:3),3,'eg_ave',lname,'W/m2',-1000.,3000.,0,itype)
    lname = 'Avg sensible heat flux'
    call attrib(idnc,jdim(1:3),3,'fg_ave',lname,'W/m2',-3000.,3000.,0,itype)
    lname = 'Avg net radiation'
    call attrib(idnc,jdim(1:3),3,'rnet_ave',lname,'none',-3000.,3000.,0,itype)
    lname = 'Avg flux into tgg1 layer'
    call attrib(idnc,jdim(1:3),3,'ga_ave',lname,'W/m2',-1000.,1000.,0,itype)
    lname = 'Avg ice water path'
    call attrib(idnc,jdim(1:3),3,'iwp_ave',lname,'kg/m2',0.,6.,0,itype)
    lname = 'Avg liquid water path'
    call attrib(idnc,jdim(1:3),3,'lwp_ave',lname,'kg/m2',0.,6.,0,itype)
    lname = 'Low cloud ave'
    call attrib(idnc,jdim(1:3),3,'cll',lname,'frac',0.,1.,0,itype)
    lname = 'Mid cloud ave'
    call attrib(idnc,jdim(1:3),3,'clm',lname,'frac',0.,1.,0,itype)
    lname = 'Hi cloud ave'
    call attrib(idnc,jdim(1:3),3,'clh',lname,'frac',0.,1.,0,itype)
    lname = 'Total cloud ave'
    call attrib(idnc,jdim(1:3),3,'cld',lname,'frac',0.,1.,0,itype)
    lname = 'Avg soil moisture 1'
    call attrib(idnc,jdim(1:3),3,'wb1_ave',lname,'m3/m3',0.,1.,0,itype)
    lname = 'Avg soil moisture 2'
    call attrib(idnc,jdim(1:3),3,'wb2_ave',lname,'m3/m3',0.,1.,0,itype)
    lname = 'Avg soil moisture 3'
    call attrib(idnc,jdim(1:3),3,'wb3_ave',lname,'m3/m3',0.,1.,0,itype)
    lname = 'Avg soil moisture 4'
    call attrib(idnc,jdim(1:3),3,'wb4_ave',lname,'m3/m3',0.,1.,0,itype)
    lname = 'Avg soil moisture 5'
    call attrib(idnc,jdim(1:3),3,'wb5_ave',lname,'m3/m3',0.,1.,0,itype)
    lname = 'Avg soil moisture 6'
    call attrib(idnc,jdim(1:3),3,'wb6_ave',lname,'m3/m3',0.,1.,0,itype)
    lname = 'Avg surface temperature'
    call attrib(idnc,jdim(1:3),3,'tsu_ave',lname,'K',100.,425.,0,itype)
    lname = 'Avg albedo'
    call attrib(idnc,jdim(1:3),3,'alb_ave',lname,'none',0.,1.,0,itype)
    lname = 'Avg mean sea level pressure'
    call attrib(idnc,jdim(1:3),3,'pmsl_ave',lname,'hPa',800.,1200.,0,itype)
    if ( abs(nmlo)>0.and.abs(nmlo)<=9 ) then
      lname = 'Avg mixed layer depth'
      call attrib(idnc,jdim(1:3),3,'mixd_ave',lname,'m',0.,1300.,0,itype)
    end if

    lname = 'Screen temperature'
    call attrib(idnc,jdim(1:3),3,'tscrn',lname,'K',100.,425.,0,itype)
    lname = 'Screen mixing ratio'
    call attrib(idnc,jdim(1:3),3,'qgscrn',lname,'kg/kg',0.,.06,0,itype)
    lname = 'Screen relative humidity'
    call attrib(idnc,jdim(1:3),3,'rhscrn',lname,'%',0.,200.,0,itype)
    lname = 'Screen level wind speed'
    call attrib(idnc,jdim(1:3),3,'uscrn',lname,'m/s',0.,65.,0,itype)
    lname = 'Net radiation'
    call attrib(idnc,jdim(1:3),3,'rnet',lname,'W/m2',-3000.,3000.,0,itype)
    lname = 'Potential "pan" evaporation'
    call attrib(idnc,jdim(1:3),3,'epan',lname,'W/m2',-1000.,10.e3,0,itype)
    lname = 'Latent heat flux'
    call attrib(idnc,jdim(1:3),3,'eg',lname,'W/m2',-1000.,3000.,0,itype)
    lname = 'Sensible heat flux'
    call attrib(idnc,jdim(1:3),3,'fg',lname,'W/m2',-3000.,3000.,0,itype)
    lname = 'x-component wind stress'
    call attrib(idnc,jdim(1:3),3,'taux',lname,'N/m2',-50.,50.,0,itype)
    lname = 'y-component wind stress'
    call attrib(idnc,jdim(1:3),3,'tauy',lname,'N/m2',-50.,50.,0,itype)
    if ( nextout>=1 ) then
      if ( myid==0 ) write(6,*) 'nextout=',nextout
      lname = 'LW at TOA'
      call attrib(idnc,jdim(1:3),3,'rtu_ave',lname,'W/m2',0.,800.,0,itype)
      lname = 'Clear sky LW at TOA'
      call attrib(idnc,jdim(1:3),3,'rtc_ave',lname,'W/m2',0.,800.,0,itype)
      lname = 'LW downwelling at ground'
      call attrib(idnc,jdim(1:3),3,'rgdn_ave',lname,'W/m2',-500.,1.e3,0,itype)
      lname = 'LW net at ground (+ve up)'
      call attrib(idnc,jdim(1:3),3,'rgn_ave',lname,'W/m2',-500.,1000.,0,itype)
      lname = 'Clear sky LW at ground'
      call attrib(idnc,jdim(1:3),3,'rgc_ave',lname,'W/m2',-500.,1000.,0,itype)
      lname = 'Solar in at TOA'
      call attrib(idnc,jdim(1:3),3,'sint_ave',lname,'W/m2',0.,1600.,0,itype)
      lname = 'Solar out at TOA'
      call attrib(idnc,jdim(1:3),3,'sot_ave',lname,'W/m2',0.,1000.,0,itype)
      lname = 'Clear sky SW out at TOA'
      call attrib(idnc,jdim(1:3),3,'soc_ave',lname,'W/m2',0.,900.,0,itype)
      lname = 'Solar downwelling at ground'
      call attrib(idnc,jdim(1:3),3,'sgdn_ave',lname,'W/m2',-500.,2.e3,0,itype)
      lname = 'Solar net at ground (+ve down)'
      call attrib(idnc,jdim(1:3),3,'sgn_ave',lname,'W/m2',-500.,2000.,0,itype)
      lname = 'Clear sky SW at ground (+ve down)'
      call attrib(idnc,jdim(1:3),3,'sgc_ave',lname,'W/m2',-500.,2000.,0,itype)
      lname = 'Sunshine hours'
      call attrib(idnc,jdim(1:3),3,'sunhours',lname,'hrs',0.,64.5,0,itype)
      lname = 'Fraction of direct radiation'
      call attrib(idnc,jdim(1:3),3,'fbeam_ave',lname,'none',-3.25,3.25,0,itype)
      lname = 'Surface pressure tendency'
      call attrib(idnc,jdim(1:3),3,'dpsdt',lname,'hPa/day',-400.,400.,0,itype)
      lname = 'friction velocity'
      call attrib(idnc,jdim(1:3),3,'ustar',lname,'m/s',0.,10.,0,itype)
    endif     ! (nextout>=1)
    if ( nextout>=1 .or. (nvmix==6.and.itype==-1) ) then
      lname = 'PBL depth'
      call attrib(idnc,jdim(1:3),3,'pblh',lname,'m',0.,13000.,0,itype)
      if ( nvmix==6 ) then
        lname = 'Dry PBL depth'
        call attrib(idnc,jdim(1:3),3,'dpblh',lname,'m',0.,13000.,0,itype)
      end if
    end if
        
    ! AEROSOL OPTICAL DEPTHS ------------------------------------
    if ( nextout>=1 .and. abs(iaero)>=2 .and. nrad==5 ) then
      lname = 'Total column small dust optical depth VIS'
      call attrib(idnc,jdim(1:3),3,'sdust_vis',lname,'none',0.,13.,0,itype)
      !lname = 'Total column small dust optical depth NIR'
      !call attrib(idnc,jdim(1:3),3,'sdust_nir',lname,'none',0.,13.,0,itype)
      !lname = 'Total column small dust optical depth LW'
      !call attrib(idnc,jdim(1:3),3,'sdust_lw',lname,'none',0.,13.,0,itype)
      lname = 'Total column large dust optical depth VIS'
      call attrib(idnc,jdim(1:3),3,'ldust_vis',lname,'none',0.,13.,0,itype)
      !lname = 'Total column large dust optical depth NIR'
      !call attrib(idnc,jdim(1:3),3,'ldust_nir',lname,'none',0.,13.,0,itype)
      !lname = 'Total column large dust optical depth LW'
      !call attrib(idnc,jdim(1:3),3,'ldust_lw',lname,'none',0.,13.,0,itype)
      lname = 'Total column sulfate optical depth VIS'
      call attrib(idnc,jdim(1:3),3,'so4_vis',lname,'none',0.,13.,0,itype)
      !lname = 'Total column sulfate optical depth NIR'
      !call attrib(idnc,jdim(1:3),3,'so4_nir',lname,'none',0.,13.,0,itype)
      !lname = 'Total column surfate optical depth LW'
      !call attrib(idnc,jdim(1:3),3,'so4_lw',lname,'none',0.,13.,0,itype)
      lname = 'Total column aerosol optical depth VIS'
      call attrib(idnc,jdim(1:3),3,'aero_vis',lname,'none',0.,13.,0,itype)
      !lname = 'Total column aerosol optical depth NIR'
      !call attrib(idnc,jdim(1:3),3,'aero_nir',lname,'none',0.,13.,0,itype)
      !lname = 'Total column aerosol optical depth LW'
      !call attrib(idnc,jdim(1:3),3,'aero_lw',lname,'none',0.,13.,0,itype)
      lname = 'Total column BC optical depth VIS'
      call attrib(idnc,jdim(1:3),3,'bc_vis',lname,'none',0.,13.,0,itype)
      !lname = 'Total column BC optical depth NIR'
      !call attrib(idnc,jdim(1:3),3,'bc_nir',lname,'none',0.,13.,0,itype)
      !lname = 'Total column BC optical depth LW'
      !call attrib(idnc,jdim(1:3),3,'bc_lw',lname,'none',0.,13.,0,itype)
      lname = 'Total column OC optical depth VIS'
      call attrib(idnc,jdim(1:3),3,'oc_vis',lname,'none',0.,13.,0,itype)
      !lname = 'Total column OC optical depth NIR'
      !call attrib(idnc,jdim(1:3),3,'oc_nir',lname,'none',0.,13.,0,itype)
      !lname = 'Total column OC optical depth LW'
      !call attrib(idnc,jdim(1:3),3,'oc_lw',lname,'none',0.,13.,0,itype)      
      lname = 'Total column seasalt optical depth VIS'
      call attrib(idnc,jdim(1:3),3,'ssalt_vis',lname,'none',0.,13.,0,itype)
      !lname = 'Total column seasalt optical depth NIR'
      !call attrib(idnc,jdim(1:3),3,'ssalt_nir',lname,'none',0.,13.,0,itype)
      !lname = 'Total column seasalt optical depth LW'
      !call attrib(idnc,jdim(1:3),3,'ssalt_lw',lname,'none',0.,13.,0,itype)      
      lname = 'Dust emissions'
      call attrib(idnc,jdim(1:3),3,'duste_ave',lname,'g/(m2 yr)',0.,13000.,0,itype)  
      lname = 'Dust dry deposition'
      call attrib(idnc,jdim(1:3),3,'dustdd_ave',lname,'g/(m2 yr)',0.,13000.,0,itype) 
      lname = 'Dust wet deposition'
      call attrib(idnc,jdim(1:3),3,'dustwd_ave',lname,'g/(m2 yr)',0.,13000.,0,itype)
      lname = 'Dust burden'
      call attrib(idnc,jdim(1:3),3,'dustb_ave',lname,'mg/m2',0.,1300.,0,itype)
      lname = 'Black carbon emissions'
      call attrib(idnc,jdim(1:3),3,'bce_ave',lname,'g/(m2 yr)',0.,390.,0,itype)  
      lname = 'Black carbon dry deposition'
      call attrib(idnc,jdim(1:3),3,'bcdd_ave',lname,'g/(m2 yr)',0.,390.,0,itype) 
      lname = 'Black carbon wet deposition'
      call attrib(idnc,jdim(1:3),3,'bcwd_ave',lname,'g/(m2 yr)',0.,390.,0,itype)
      lname = 'Black carbon burden'
      call attrib(idnc,jdim(1:3),3,'bcb_ave',lname,'mg/m2',0.,130.,0,itype)
      lname = 'Organic carbon emissions'
      call attrib(idnc,jdim(1:3),3,'oce_ave',lname,'g/(m2 yr)',0.,390.,0,itype)  
      lname = 'Organic carbon dry deposition'
      call attrib(idnc,jdim(1:3),3,'ocdd_ave',lname,'g/(m2 yr)',0.,390.,0,itype) 
      lname = 'Organic carbon wet deposition'
      call attrib(idnc,jdim(1:3),3,'ocwd_ave',lname,'g/(m2 yr)',0.,390.,0,itype)
      lname = 'Organic carbon burden'
      call attrib(idnc,jdim(1:3),3,'ocb_ave',lname,'mg/m2',0.,130.,0,itype)
      lname = 'DMS emissions'
      call attrib(idnc,jdim(1:3),3,'dmse_ave',lname,'gS/(m2 yr)',0.,390.,0,itype) 
      lname = 'DMS to SO2 oxidation'
      call attrib(idnc,jdim(1:3),3,'dmsso2_ave',lname,'gS/(m2 yr)',0.,390.,0,itype)
      lname = 'SO2 emissions'
      call attrib(idnc,jdim(1:3),3,'so2e_ave',lname,'gS/(m2 yr)',0.,390.,0,itype) 
      lname = 'SO2 to SO4 oxidation'
      call attrib(idnc,jdim(1:3),3,'so2so4_ave',lname,'gS/(m2 yr)',0.,390.,0,itype)
      lname = 'SO2 dry deposition'
      call attrib(idnc,jdim(1:3),3,'so2dd_ave',lname,'gS/(m2 yr)',0.,390.,0,itype)
      lname = 'SO2 wet deposition'
      call attrib(idnc,jdim(1:3),3,'so2wd_ave',lname,'gS/(m2 yr)',0.,390.,0,itype)
      lname = 'SO4 emissions'
      call attrib(idnc,jdim(1:3),3,'so4e_ave',lname,'gS/(m2 yr)',0.,390.,0,itype)
      lname = 'SO4 dry deposition'
      call attrib(idnc,jdim(1:3),3,'so4dd_ave',lname,'gS/(m2 yr)',0.,390.,0,itype) 
      lname = 'SO4 wet deposition'
      call attrib(idnc,jdim(1:3),3,'so4wd_ave',lname,'gS/(m2 yr)',0.,390.,0,itype) 
      lname = 'DMS burden'
      call attrib(idnc,jdim(1:3),3,'dmsb_ave',lname,'mgS/m2',0.,13.,0,itype) 
      lname = 'SO2 burden'
      call attrib(idnc,jdim(1:3),3,'so2b_ave',lname,'mgS/m2',0.,13.,0,itype) 
      lname = 'SO4 burden'
      call attrib(idnc,jdim(1:3),3,'so4b_ave',lname,'mgS/m2',0.,13.,0,itype) 
    end if

    ! CABLE -----------------------------------------------------
    if ( nsib==6 .or. nsib==7 ) then
      if ( nextout>=1 .or. itype==-1 ) then
        if ( ccycle==0 ) then
          !lname = 'Carbon leaf pool'
          !call attrib(idnc,jdim(1:3),3,'cplant1',lname,'gC/m2',0.,6500.,0,itype)
          !lname = 'Carbon wood pool'
          !call attrib(idnc,jdim(1:3),3,'cplant2',lname,'gC/m2',0.,65000.,0,itype)
          !lname = 'Carbon root pool'
          !call attrib(idnc,jdim(1:3),3,'cplant3',lname,'gC/m2',0.,6500.,0,itype)
          !lname = 'Carbon soil fast pool'
          !call attrib(idnc,jdim(1:3),3,'csoil1',lname,'gC/m2',0.,6500.,0,itype)
          !lname = 'Carbon soil slow pool'
          !call attrib(idnc,jdim(1:3),3,'csoil2',lname,'gC/m2',0.,6500.,0,itype)
        else
          lname = 'Carbon leaf pool'
          call attrib(idnc,jdim(1:3),3,'cplant1',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Nitrogen leaf pool'
          call attrib(idnc,jdim(1:3),3,'nplant1',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Phosphor leaf pool'
          call attrib(idnc,jdim(1:3),3,'pplant1',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Carbon wood pool'
          call attrib(idnc,jdim(1:3),3,'cplant2',lname,'gC/m2',0.,65000.,0,itype)
          lname = 'Nitrogen wood pool'
          call attrib(idnc,jdim(1:3),3,'nplant2',lname,'gC/m2',0.,65000.,0,itype)
          lname = 'Phosphor wood pool'
          call attrib(idnc,jdim(1:3),3,'pplant2',lname,'gC/m2',0.,65000.,0,itype)
          lname = 'Carbon root pool'
          call attrib(idnc,jdim(1:3),3,'cplant3',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Nitrogen root pool'
          call attrib(idnc,jdim(1:3),3,'nplant3',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Phosphor root pool'
          call attrib(idnc,jdim(1:3),3,'pplant3',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Carbon met pool'
          call attrib(idnc,jdim(1:3),3,'clitter1',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Nitrogen met pool'
          call attrib(idnc,jdim(1:3),3,'nlitter1',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Phosphor met pool'
          call attrib(idnc,jdim(1:3),3,'plitter1',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Carbon str pool'
          call attrib(idnc,jdim(1:3),3,'clitter2',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Nitrogen str pool'
          call attrib(idnc,jdim(1:3),3,'nlitter2',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Phosphor str pool'
          call attrib(idnc,jdim(1:3),3,'plitter2',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Carbon CWD pool'
          call attrib(idnc,jdim(1:3),3,'clitter3',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Nitrogen CWD pool'
          call attrib(idnc,jdim(1:3),3,'nlitter3',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Phosphor CWD pool'
          call attrib(idnc,jdim(1:3),3,'plitter3',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Carbon mic pool'
          call attrib(idnc,jdim(1:3),3,'csoil1',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Nitrogen mic pool'
          call attrib(idnc,jdim(1:3),3,'nsoil1',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Phosphor mic pool'
          call attrib(idnc,jdim(1:3),3,'psoil1',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Carbon slow pool'
          call attrib(idnc,jdim(1:3),3,'csoil2',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Nitrogen slow pool'
          call attrib(idnc,jdim(1:3),3,'nsoil2',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Phosphor slow pool'
          call attrib(idnc,jdim(1:3),3,'psoil2',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Carbon pass pool'
          call attrib(idnc,jdim(1:3),3,'csoil3',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Nitrogen pass pool'
          call attrib(idnc,jdim(1:3),3,'nsoil3',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Phosphor pass pool'
          call attrib(idnc,jdim(1:3),3,'psoil3',lname,'gC/m2',0.,6500.,0,itype)
          lname = 'Prognostic LAI'
          call attrib(idnc,jdim(1:3),3,'glai',lname,'none',0.,13.,0,itype)
        end if
      end if
      if ( nextout>=1 .and. itype/=-1 ) then
        lname = 'Avg Net CO2 flux'
        call attrib(idnc,jdim(1:3),3,'fnee_ave',lname,'gC/m2/s',-3.25E-3,3.25E-3,0,itype)
        lname = 'Avg Photosynthesis CO2 flux'
        call attrib(idnc,jdim(1:3),3,'fpn_ave',lname,'gC/m2/s',-3.25E-3,3.25E-3,0,itype)
        lname = 'Avg Plant respiration CO2 flux'
        call attrib(idnc,jdim(1:3),3,'frp_ave',lname,'gC/m2/s',-3.25E-3,3.25E-3,0,itype)
        lname = 'Avg Soil respiration CO2 flux'
        call attrib(idnc,jdim(1:3),3,'frs_ave',lname,'gC/m2/s',-3.25E-3,3.25E-3,0,itype)
      end if
    end if

    ! URBAN -----------------------------------------------------
    if ( nurban<=-1 .or. (nurban>=1.and.itype==-1) ) then
      lname = 'roof temperature lev 1'
      call attrib(idnc,jdim(1:3),3,'rooftgg1',lname,'K',100.,425.,0,itype)
      lname = 'roof temperature lev 2'
      call attrib(idnc,jdim(1:3),3,'rooftgg2',lname,'K',100.,425.,0,itype)
      lname = 'roof temperature lev 3'
      call attrib(idnc,jdim(1:3),3,'rooftgg3',lname,'K',100.,425.,0,itype)
      lname = 'roof temperature lev 4'
      call attrib(idnc,jdim(1:3),3,'rooftgg4',lname,'K',100.,425.,0,itype)
      lname = 'roof temperature lev 5'
      call attrib(idnc,jdim(1:3),3,'rooftgg5',lname,'K',100.,425.,0,itype)
      lname = 'east wall temperature lev 1'
      call attrib(idnc,jdim(1:3),3,'waletgg1',lname,'K',100.,425.,0,itype)
      lname = 'east wall temperature lev 2'
      call attrib(idnc,jdim(1:3),3,'waletgg2',lname,'K',100.,425.,0,itype)
      lname = 'east wall temperature lev 3'
      call attrib(idnc,jdim(1:3),3,'waletgg3',lname,'K',100.,425.,0,itype)
      lname = 'east wall temperature lev 4'
      call attrib(idnc,jdim(1:3),3,'waletgg4',lname,'K',100.,425.,0,itype)
      lname = 'east wall temperature lev 5'
      call attrib(idnc,jdim(1:3),3,'waletgg5',lname,'K',100.,425.,0,itype)
      lname = 'west wall temperature lev 1'
      call attrib(idnc,jdim(1:3),3,'walwtgg1',lname,'K',100.,425.,0,itype)
      lname = 'west wall temperature lev 2'
      call attrib(idnc,jdim(1:3),3,'walwtgg2',lname,'K',100.,425.,0,itype)
      lname = 'west wall temperature lev 3'
      call attrib(idnc,jdim(1:3),3,'walwtgg3',lname,'K',100.,425.,0,itype)
      lname = 'west wall temperature lev 4'
      call attrib(idnc,jdim(1:3),3,'walwtgg4',lname,'K',100.,425.,0,itype)
      lname = 'west wall temperature lev 5'
      call attrib(idnc,jdim(1:3),3,'walwtgg5',lname,'K',100.,425.,0,itype)
      lname = 'road temperature lev 1'
      call attrib(idnc,jdim(1:3),3,'roadtgg1',lname,'K',100.,425.,0,itype)
      lname = 'road temperature lev 2'
      call attrib(idnc,jdim(1:3),3,'roadtgg2',lname,'K',100.,425.,0,itype)
      lname = 'road temperature lev 3'
      call attrib(idnc,jdim(1:3),3,'roadtgg3',lname,'K',100.,425.,0,itype)
      lname = 'road temperature lev 4'
      call attrib(idnc,jdim(1:3),3,'roadtgg4',lname,'K',100.,425.,0,itype)
      lname = 'road temperature lev 5'
      call attrib(idnc,jdim(1:3),3,'roadtgg5',lname,'K',100.,425.,0,itype)
      lname = 'urban canyon soil moisture'
      call attrib(idnc,jdim(1:3),3,'urbnsmc',lname,'m3/m3',0.,1.3,0,itype)
      lname = 'urban roof soil moisture'
      call attrib(idnc,jdim(1:3),3,'urbnsmr',lname,'m3/m3',0.,1.3,0,itype)
      lname = 'urban roof water'
      call attrib(idnc,jdim(1:3),3,'roofwtr',lname,'mm',0.,1.3,0,itype)
      lname = 'urban road water'
      call attrib(idnc,jdim(1:3),3,'roadwtr',lname,'mm',0.,1.3,0,itype)
      lname = 'urban canyon leaf water'
      call attrib(idnc,jdim(1:3),3,'urbwtrc',lname,'mm',0.,1.3,0,itype)
      lname = 'urban roof leaf water'
      call attrib(idnc,jdim(1:3),3,'urbwtrr',lname,'mm',0.,1.3,0,itype)
      lname = 'urban roof snow (liquid water)'
      call attrib(idnc,jdim(1:3),3,'roofsnd',lname,'mm',0.,1.3,0,itype)
      lname = 'urban road snow (liquid water)'
      call attrib(idnc,jdim(1:3),3,'roadsnd',lname,'mm',0.,1.3,0,itype)
      lname = 'urban roof snow density'
      call attrib(idnc,jdim(1:3),3,'roofden',lname,'kg/m3',0.,650.,0,itype)
      lname = 'urban road snow density'
      call attrib(idnc,jdim(1:3),3,'roadden',lname,'kg/m3',0.,650.,0,itype)
      lname = 'urban roof snow albedo'
      call attrib(idnc,jdim(1:3),3,'roofsna',lname,'none',0.,1.3,0,itype)
      lname = 'urban road snow albedo'
      call attrib(idnc,jdim(1:3),3,'roadsna',lname,'none',0.,1.3,0,itype)
    end if
        
    ! STANDARD 3D VARIABLES -------------------------------------
    if ( myid==0 ) write(6,*) '3d variables'
    if ( nextout>=4 .and. nllp==3 ) then   ! N.B. use nscrn=1 for hourly output
      lname = 'Delta latitude'
      call attrib(idnc,idim(1:4),4,'del_lat',lname,'deg',-60.,60.,1,itype)
      lname = 'Delta longitude'
      call attrib(idnc,idim(1:4),4,'del_lon',lname,'deg',-180.,180.,1,itype)
      lname = 'Delta pressure'
      call attrib(idnc,idim(1:4),4,'del_p',lname,'hPa',-900.,900.,1,itype)
    endif  ! (nextout>=4.and.nllp==3)
    lname = 'Air temperature'
    call attrib(idnc,idim(1:4),4,'temp',lname,'K',100.,350.,0,itype)
    lname = 'x-component wind'
    call attrib(idnc,idim(1:4),4,'u',lname,'m/s',-150.,150.,0,itype)
    lname = 'y-component wind'
    call attrib(idnc,idim(1:4),4,'v',lname,'m/s',-150.,150.,0,itype)
    lname = 'vertical velocity'
    call attrib(idnc,idim(1:4),4,'omega',lname,'Pa/s',-65.,65.,0,itype)
    lname = 'Water mixing ratio'
    call attrib(idnc,idim(1:4),4,'mixr',lname,'kg/kg',0.,.065,0,itype)
    lname = 'Covective heating'
    call attrib(idnc,idim(1:4),4,'convh_ave',lname,'K/day',-10.,20.,0,itype)
        
    ! CLOUD MICROPHYSICS --------------------------------------------
    if ( ldr/=0 ) then
      call attrib(idnc,idim(1:4),4,'qfg','Frozen water','kg/kg',0.,.065,0,itype)
      call attrib(idnc,idim(1:4),4,'qlg','Liquid water','kg/kg',0.,.065,0,itype)
      if ( ncloud>=2 ) then
        call attrib(idnc,idim(1:4),4,'qrg','Rain',        'kg/kg',0.,.065,0,itype)
      end if
      if ( ncloud>=3 ) then
        call attrib(idnc,idim(1:4),4,'qsng','Snow',       'kg/kg',0.,.065,0,itype)
        call attrib(idnc,idim(1:4),4,'qgrg','Graupel',    'kg/kg',0.,.065,0,itype)
      end if
      call attrib(idnc,idim(1:4),4,'cfrac','Cloud fraction',  'none',0.,1.,0,itype)
      if ( ncloud>=2 ) then
        call attrib(idnc,idim(1:4),4,'rfrac','Rain fraction',   'none',0.,1.,0,itype)
      end if
      if ( ncloud>=3 ) then
        call attrib(idnc,idim(1:4),4,'sfrac','Snow fraction',   'none',0.,1.,0,itype)
        call attrib(idnc,idim(1:4),4,'gfrac','Graupel fraction','none',0.,1.,0,itype)
      end if
      if ( ncloud>=4 ) then
        call attrib(idnc,idim(1:4),4,'stratcf','Strat cloud fraction','none',0.,1.,0,itype)
        if ( itype==-1 ) then
          call attrib(idnc,idim(1:4),4,'strat_nt','Strat net temp tendency','K/s',0.,1.,0,itype)
        end if
      end if
    end if
        
    ! TURBULENT MIXING ----------------------------------------------
    if ( nvmix==6 .and. (nextout>=1.or.itype==-1) ) then
      call attrib(idnc,idim(1:4),4,'tke','Turbulent Kinetic Energy','m2/s2',0.,65.,0,itype)
      call attrib(idnc,idim(1:4),4,'eps','Eddy dissipation rate','m2/s3',0.,6.5,0,itype)
    end if

    ! TRACER --------------------------------------------------------
    if ( ngas>0 ) then
      if ( itype==-1 ) then ! restart
        do igas=1,ngas
          write(trnum,'(i3.3)') igas
          lname = 'Tracer (inst.) '//trim(tracname(igas))
          call attrib(idnc,idim(1:4),4,'tr'//trnum,lname,'ppm',0.,6.5E6,0,-1) ! -1 = long
        enddo ! igas loop
      else                  ! history
        do igas=1,ngas
          write(trnum,'(i3.3)') igas
!         rml 19/09/07 use tracname as part of tracer long name
          !lname = 'Tracer (inst.) '//trim(tracname(igas))
          !call attrib(idnc,idim(1:4),4,'tr'//trnum,lname,'ppm',0.,6.5E6,0,-1) ! -1 = long
          lname = 'Tracer (average) '//trim(tracname(igas))
          call attrib(idnc,idim(1:4),4,'trav'//trnum,lname,'ppm',0.,6.5E6,0,-1) ! -1 = long
!         rml 14/5/10 option to write out local time afternoon averages
          if (writetrpm) call attrib(idnc,idim(1:4),4,'trpm'//trnum,lname,'ppm',0.,6.5E6,0,-1) ! -1 = long
        enddo ! igas loop
      end if
    endif   ! (ngas>0)

    ! AEROSOL ---------------------------------------------------
    if ( abs(iaero)>=2 ) then  
      call attrib(idnc,idim(1:4),4,'dms','Dimethyl sulfide','kg/kg',0.,6.5E-7,0,itype)
      call attrib(idnc,idim(1:4),4,'so2','Sulfur dioxide','kg/kg',0.,6.5E-7,0,itype)
      call attrib(idnc,idim(1:4),4,'so4','Sulfate','kg/kg',0.,6.5E-7,0,itype)
      call attrib(idnc,idim(1:4),4,'bco','Black carbon hydrophobic','kg/kg',0.,6.5E-6,0,itype)
      call attrib(idnc,idim(1:4),4,'bci','Black carbon hydrophilic','kg/kg',0.,6.5E-6,0,itype)
      call attrib(idnc,idim(1:4),4,'oco','Organic aerosol hydrophobic','kg/kg',0.,6.5E-6,0,itype)
      call attrib(idnc,idim(1:4),4,'oci','Organic aerosol hydrophilic','kg/kg',0.,6.5E-6,0,itype)
      call attrib(idnc,idim(1:4),4,'dust1','Dust 0.1-1 micrometers','kg/kg',0.,6.5E-6,0,itype)
      call attrib(idnc,idim(1:4),4,'dust2','Dust 1-2 micrometers','kg/kg',0.,6.5E-6,0,itype)
      call attrib(idnc,idim(1:4),4,'dust3','Dust 2-3 micrometers','kg/kg',0.,6.5E-6,0,itype)
      call attrib(idnc,idim(1:4),4,'dust4','Dust 3-6 micrometers','kg/kg',0.,6.5E-6,0,itype)
      call attrib(idnc,idim(1:4),4,'seasalt1','Sea salt small','1/m3',0.,6.5E9,0,itype)
      call attrib(idnc,idim(1:4),4,'seasalt2','Sea salt large','1/m3',0.,6.5E7,0,itype)
      if ( iaero<=-2 ) then 
        call attrib(idnc,idim(1:4),4,'cdn','Cloud droplet concentration','1/m3',1.E7,6.6E8,0,itype)
      end if
    end if
    
    ! RESTART ---------------------------------------------------
    if ( itype==-1 ) then   ! extra stuff just written for restart file
      lname= 'Tendency of surface pressure'
      call attrib(idnc,idim(1:4),4,'dpsldt',lname,'1/s',-6.,6.,0,itype)        
      lname= 'NHS adjustment to geopotential height'
      call attrib(idnc,idim(1:4),4,'zgnhs',lname,'m2/s2',-6.E5,6.E5,0,itype)     
      lname= 'sdot: change in grid spacing per time step +.5'
      call attrib(idnc,idim(1:4),4,'sdot',lname,'1/ts',-3.,3.,0,itype) 
      lname= 'pslx: advective time rate of change of psl'
      call attrib(idnc,idim(1:4),4,'pslx',lname,'1/s',-1.E-3,1.E-3,0,itype)
      lname= 'savu'
      call attrib(idnc,idim(1:4),4,'savu',lname,'m/s',-1.E2,1.E2,0,itype)
      lname= 'savv'
      call attrib(idnc,idim(1:4),4,'savv',lname,'m/s',-1.E2,1.E2,0,itype)
      lname= 'savu1'
      call attrib(idnc,idim(1:4),4,'savu1',lname,'m/s',-1.E2,1.E2,0,itype)
      lname= 'savv1'
      call attrib(idnc,idim(1:4),4,'savv1',lname,'m/s',-1.E2,1.E2,0,itype)
      lname= 'savu2'
      call attrib(idnc,idim(1:4),4,'savu2',lname,'m/s',-1.E2,1.E2,0,itype)
      lname= 'savv2'
      call attrib(idnc,idim(1:4),4,'savv2',lname,'m/s',-1.E2,1.E2,0,itype)
      if ( abs(nmlo)>=3 .and. abs(nmlo)<=9 ) then
        do k=1,wlev
          write(lname,'("oldu1 ",I2)') k
          write(vname,'("oldu1",I2.2)') k
          call attrib(idnc,jdim(1:3),3,vname,lname,'m/s',-100.,100.,0,itype)
          write(lname,'("oldv1 ",I2)') k
          write(vname,'("oldv1",I2.2)') k
          call attrib(idnc,jdim(1:3),3,vname,lname,'m/s',-100.,100.,0,itype)
          write(lname,'("oldu2 ",I2)') k
          write(vname,'("oldu2",I2.2)') k
          call attrib(idnc,jdim(1:3),3,vname,lname,'m/s',-100.,100.,0,itype)
          write(lname,'("oldv2 ",I2)') k
          write(vname,'("oldv2",I2.2)') k
          call attrib(idnc,jdim(1:3),3,vname,lname,'m/s',-100.,100.,0,itype)
        end do
        lname= 'ipice'
        call attrib(idnc,jdim(1:3),3,'ipice',lname,'Pa',0.,1.E6,0,itype)
      end if
      lname = 'Soil ice lev 1'
      call attrib(idnc,jdim(1:3),3,'wbice1',lname,'m3/m3',0.,1.,0,itype)
      lname = 'Soil ice lev 2'
      call attrib(idnc,jdim(1:3),3,'wbice2',lname,'m3/m3',0.,1.,0,itype)
      lname = 'Soil ice lev 3'
      call attrib(idnc,jdim(1:3),3,'wbice3',lname,'m3/m3',0.,1.,0,itype)
      lname = 'Soil ice lev 4'
      call attrib(idnc,jdim(1:3),3,'wbice4',lname,'m3/m3',0.,1.,0,itype)
      lname = 'Soil ice lev 5'
      call attrib(idnc,jdim(1:3),3,'wbice5',lname,'m3/m3',0.,1.,0,itype)
      lname = 'Soil ice lev 6'
      call attrib(idnc,jdim(1:3),3,'wbice6',lname,'m3/m3',0.,1.,0,itype)
      if ( nmlo==0 ) then ! otherwise already defined above
        lname = 'Snow temperature lev 1'
        call attrib(idnc,jdim(1:3),3,'tggsn1',lname,'K',100.,425.,0,itype)
        lname = 'Snow temperature lev 2'
        call attrib(idnc,jdim(1:3),3,'tggsn2',lname,'K',100.,425.,0,itype)
        lname = 'Snow temperature lev 3'
        call attrib(idnc,jdim(1:3),3,'tggsn3',lname,'K',100.,425.,0,itype)
      end if
      lname = 'Snow mass lev 1'
      call attrib(idnc,jdim(1:3),3,'smass1',lname,'K',0.,425.,0,itype)
      lname = 'Snow mass lev 2'
      call attrib(idnc,jdim(1:3),3,'smass2',lname,'K',0.,425.,0,itype)
      lname = 'Snow mass lev 3'
      call attrib(idnc,jdim(1:3),3,'smass3',lname,'K',0.,425.,0,itype)
      lname = 'Snow density lev 1'
      call attrib(idnc,jdim(1:3),3,'ssdn1',lname,'K',0.,425.,0,itype)
      lname = 'Snow density lev 2'
      call attrib(idnc,jdim(1:3),3,'ssdn2',lname,'K',0.,425.,0,itype)
      lname = 'Snow density lev 3'
      call attrib(idnc,jdim(1:3),3,'ssdn3',lname,'K',0.,425.,0,itype)
      lname = 'Snow age'
      call attrib(idnc,jdim(1:3),3,'snage',lname,'none',0.,20.,0,itype)   
      lname = 'Snow flag'
      call attrib(idnc,jdim(1:3),3,'sflag',lname,'none',0.,4.,0,itype)
      lname = 'Solar net at ground (+ve down)'
      call attrib(idnc,jdim(1:3),3,'sgsave',lname,'W/m2',-500.,2000.,0,itype)
      if ( nsib==6 .or. nsib==7 ) then
        call savetiledef(idnc,local,jdim)
      end if
    endif  ! (itype==-1)
        
    if ( myid==0 ) write(6,*) 'finished defining attributes'
!   Leave define mode
    call ccnf_enddef(idnc)
    if ( myid==0 ) write(6,*) 'leave define mode'

    if ( local ) then
      ! Set these to global indices (relative to panel 0 in uniform decomp)
      do i=1,ipan
        xpnt(i) = float(i) + ioff
      end do
      call ccnf_put_vara(idnc,ixp,1,il,xpnt(1:il))
      i=1
      do n=1,npan
        do j=1,jpan
          ypnt(i) = float(j) + joff + (n-noff)*il_g
          i=i+1
        end do
      end do
      call ccnf_put_vara(idnc,iyp,1,jl,ypnt(1:jl))
    else
      do i=1,il_g
        xpnt(i) = float(i)
      end do
      call ccnf_put_vara(idnc,ixp,1,il_g,xpnt(1:il_g))
      do j=1,jl_g
        ypnt(j) = float(j)
      end do
      call ccnf_put_vara(idnc,iyp,1,jl_g,ypnt(1:jl_g))
    endif

    call ccnf_put_vara(idnc,idlev,1,kl,sig)
    call ccnf_put_vara(idnc,'sigma',1,kl,sig)

    zsoil(1)=0.5*zse(1)
    zsoil(2)=zse(1)+zse(2)*0.5
    zsoil(3)=zse(1)+zse(2)+zse(3)*0.5
    zsoil(4)=zse(1)+zse(2)+zse(3)+zse(4)*0.5
    zsoil(5)=zse(1)+zse(2)+zse(3)+zse(4)+zse(5)*0.5
    zsoil(6)=zse(1)+zse(2)+zse(3)+zse(4)+zse(5)+zse(6)*0.5
    call ccnf_put_vara(idnc,idms,1,ms,zsoil)
        
    if ( abs(nmlo)>0 .and. abs(nmlo)<=9 ) then
      call ccnf_put_vara(idnc,idoc,1,wlev,gosig)
    end if

    call ccnf_put_vara(idnc,'ds',1,ds)
    call ccnf_put_vara(idnc,'dt',1,dt)
    
  endif ! iarch==1
  ! -----------------------------------------------------------      

  ! set time to number of minutes since start 
  call ccnf_put_vara(idnc,'time',iarch,real(mtimer))
  call ccnf_put_vara(idnc,'timer',iarch,timer)   ! to be depreciated
  call ccnf_put_vara(idnc,'mtimer',iarch,mtimer) ! to be depreciated
  call ccnf_put_vara(idnc,'timeg',iarch,timeg)   ! to be depreciated
  call ccnf_put_vara(idnc,'ktau',iarch,ktau)     ! to be depreciated
  call ccnf_put_vara(idnc,'kdate',iarch,kdate)   ! to be depreciated 
  call ccnf_put_vara(idnc,'ktime',iarch,ktime)   ! to be depreciated
  call ccnf_put_vara(idnc,'nstag',iarch,nstag)
  call ccnf_put_vara(idnc,'nstagu',iarch,nstagu)
  idum = mod(ktau-nstagoff,max(abs(nstagin),1))
  idum = idum - max(abs(nstagin),1) ! should be -ve
  call ccnf_put_vara(idnc,'nstagoff',iarch,idum)
  if ( (nmlo<0.and.nmlo>=-9) .or. (nmlo>0.and.nmlo<=9.and.itype==-1) ) then
    idum = mod(ktau-nstagoffmlo,max(2*mstagf,1))
    idum = idum - max(2*mstagf,1) ! should be -ve
    call ccnf_put_vara(idnc,'nstagoffmlo',iarch,idum)
  end if
  if ( myid==0 ) then
    write(6,*) 'kdate,ktime,ktau=',kdate,ktime,ktau
    write(6,*) 'timer,timeg=',timer,timeg
  end if
       
endif ! myid == 0 .or. local

! Export ocean data
if ( nmlo/=0 .and. abs(nmlo)<=9 ) then
  mlodwn(:,:,1:2) = 999.
  mlodwn(:,:,3:4) = 0.
  micdwn(:,:)     = 999.
  micdwn(:,8)     = 0.
  micdwn(:,9)     = 0.
  micdwn(:,10)    = 0.
  ocndep(:)       = 0. ! ocean depth
  ocnheight(:)    = 0. ! free surface height
  call mlosave(mlodwn,ocndep,ocnheight,micdwn,0)
end if        

!**************************************************************
! WRITE TIME-INVARIANT VARIABLES
!**************************************************************

if ( ktau==0 .or. itype==-1 ) then  ! also for restart file
  call histwrt3(zs,'zht',idnc,iarch,local,.true.)
  call histwrt3(he,'he',idnc,iarch,local,.true.)
  call histwrt3(em,'map',idnc,iarch,local,.true.)
  call histwrt3(f,'cor',idnc,iarch,local,.true.)
  call histwrt3(sigmu,'sigmu',idnc,iarch,local,.true.)
  aa(:) = real(isoilm_in(:)) ! use the raw soil data here
  call histwrt3(aa,'soilt',idnc,iarch,local,.true.)
  aa(:) = real(ivegt(:))
  call histwrt3(aa,'vegt',idnc,iarch,local,.true.)
  if ( (nmlo<0.and.nmlo>=-9) .or. (nmlo>0.and.nmlo<=9.and.itype==-1) ) then
    call histwrt3(ocndep,'ocndepth',idnc,iarch,local,.true.)
  end if
endif ! (ktau==0.or.itype==-1) 

!**************************************************************
! WRITE 3D VARIABLES (2D + Time)
!**************************************************************

! BASIC -------------------------------------------------------
lwrite = ktau>0
if ( nsib==6 .or. nsib==7 ) then
  call histwrt3(rsmin,'rs',idnc,iarch,local,lwrite)
else if (ktau==0.or.itype==-1) then
  call histwrt3(rsmin,'rsmin',idnc,iarch,local,.true.)
end if
call histwrt3(sigmf,'sigmf',idnc,iarch,local,.true.)
call histwrt3(psl,'psf',idnc,iarch,local,.true.)
call mslp(aa,psl,zs,t)
aa(:) = aa(:)/100.
call histwrt3(aa,'pmsl',idnc,iarch,local,.true.)
if ( nsib==6 .or. nsib==7 ) then      
  call histwrt3(zo,'zolnd',idnc,iarch,local,lwrite)
else
  call histwrt3(zo,'zolnd',idnc,iarch,local,.true.)
end if
call histwrt3(vlai,'lai',idnc,iarch,local,.true.)
call histwrt3(tss,'tsu',idnc,iarch,local,.true.)
call histwrt3(tpan,'tpan',idnc,iarch,local,.true.)
! scale up precip,precc,sno,runoff to mm/day (soon reset to 0 in globpe)
! ktau in next line in case ntau (& thus ktau) < nwt 
aa(:) = precip(1:ifull)*real(nperday)/real(min(nwt,max(ktau,1))) 
call histwrt3(aa,'rnd',idnc,iarch,local,lwrite)
aa(:) = precc(1:ifull)*real(nperday)/real(min(nwt,max(ktau,1)))
call histwrt3(aa,'rnc',idnc,iarch,local,lwrite)
aa(:) = sno(1:ifull)*real(nperday)/real(min(nwt,max(ktau,1)))
call histwrt3(aa,'sno',idnc,iarch,local,lwrite)
aa(:) = grpl(1:ifull)*real(nperday)/real(min(nwt,max(ktau,1)))
call histwrt3(aa,'grpl',idnc,iarch,local,lwrite)
aa(:) = runoff(1:ifull)*real(nperday)/real(min(nwt,max(ktau,1)))
call histwrt3(aa,'runoff',idnc,iarch,local,lwrite)
aa(:) = swrsave*albvisnir(:,1)+(1.-swrsave)*albvisnir(:,2)
call histwrt3(aa,'alb',idnc,iarch,local,.true.)
call histwrt3(fwet,'fwet',idnc,iarch,local,lwrite)

! MLO ---------------------------------------------------------      
if ( nmlo/=0 .and. abs(nmlo)<=9 ) then
  ocnheight = min(max(ocnheight,-130.),130.)
  do k=1,ms
    where (.not.land(1:ifull))
      tgg(:,k) = mlodwn(:,k,1)
    end where
  end do
  do k=1,3
    where (.not.land(1:ifull))
      tggsn(:,k) = micdwn(:,k)
    end where
  end do
  where (.not.land(1:ifull))
    fracice = micdwn(:,5)
    sicedep = micdwn(:,6)
    snowd   = micdwn(:,7)*1000.
  end where
end if

call histwrt3(snowd,'snd', idnc,iarch,local,.true.)  ! long write
do k=1,ms
  where ( tgg(:,k)<100. .and. itype==1 )
    aa(:)=tgg(:,k)+wrtemp
  elsewhere
    aa(:)=tgg(:,k)      ! Allows ocean temperatures to use a 290K offset
  end where
  write(vname,'("tgg",I1.1)') k
  call histwrt3(aa,vname,idnc,iarch,local,.true.)
  where ( tgg(:,k)<100. )
    tgg(:,k)=tgg(:,k)+wrtemp
  end where
end do

if ( abs(nmlo)<=9 ) then
  if ( nmlo<0 .or. (nmlo>0.and.itype==-1) ) then
    if ( itype==1 ) then
      do k=ms+1,wlev
        write(vname,'("tgg",I2.2)') k        
        aa(:)=mlodwn(:,k,1)+wrtemp
        call histwrt3(aa,vname,idnc,iarch,local,.true.)
      end do
    else
      do k=ms+1,wlev
        write(vname,'("tgg",I2.2)') k        
        call histwrt3(mlodwn(:,k,1),vname,idnc,iarch,local,.true.)
      end do
    end if 
    do k=1,wlev
      write(vname,'("sal",I2.2)') k
      call histwrt3(mlodwn(:,k,2),vname,idnc,iarch,local,.true.)
    end do
    do k=1,wlev
      write(vname,'("uoc",I2.2)') k
      call histwrt3(mlodwn(:,k,3),vname,idnc,iarch,local,.true.)
      write(vname,'("voc",I2.2)') k
      call histwrt3(mlodwn(:,k,4),vname,idnc,iarch,local,.true.)
    end do
    call histwrt3(ocnheight,'ocheight',idnc,iarch,local,.true.)
    call histwrt3(tggsn(:,1),'tggsn1',idnc,iarch,local,.true.)
    call histwrt3(tggsn(:,2),'tggsn2',idnc,iarch,local,.true.)
    call histwrt3(tggsn(:,3),'tggsn3',idnc,iarch,local,.true.)
    call histwrt3(micdwn(:,4),'tggsn4',idnc,iarch,local,.true.)
    call histwrt3(micdwn(:,8),'sto',idnc,iarch,local,.true.)
    call histwrt3(micdwn(:,9),'uic',idnc,iarch,local,.true.)
    call histwrt3(micdwn(:,10),'vic',idnc,iarch,local,.true.)
    call histwrt3(micdwn(:,11),'icesal',idnc,iarch,local,.true.)
  end if
end if
if ( nmlo<=-2 .or. (nmlo>=2.and.itype==-1) .or. nriver==1 ) then
  call histwrt3(watbdy(1:ifull),'swater',idnc,iarch,local,.true.)
end if

! SOIL --------------------------------------------------------
aa(:)=(wb(:,1)-swilt(isoilm))/(sfc(isoilm)-swilt(isoilm))
call histwrt3(aa,'wetfrac1',idnc,iarch,local,.true.)
aa(:)=(wb(:,2)-swilt(isoilm))/(sfc(isoilm)-swilt(isoilm))
call histwrt3(aa,'wetfrac2',idnc,iarch,local,.true.)
aa(:)=(wb(:,3)-swilt(isoilm))/(sfc(isoilm)-swilt(isoilm))
call histwrt3(aa,'wetfrac3',idnc,iarch,local,.true.)
aa(:)=(wb(:,4)-swilt(isoilm))/(sfc(isoilm)-swilt(isoilm))
call histwrt3(aa,'wetfrac4',idnc,iarch,local,.true.)
aa(:)=(wb(:,5)-swilt(isoilm))/(sfc(isoilm)-swilt(isoilm))
call histwrt3(aa,'wetfrac5',idnc,iarch,local,.true.)
aa(:)=(wb(:,6)-swilt(isoilm))/(sfc(isoilm)-swilt(isoilm))
call histwrt3(aa,'wetfrac6',idnc,iarch,local,.true.)
      
! PH - Add wetfac to output for mbase=-19 option
call histwrt3(wetfac,'wetfac',idnc,iarch,local,.true.)
      
! SEAICE ------------------------------------------------------       
call histwrt3(sicedep,'siced',idnc,iarch,local,.true.)
call histwrt3(fracice,'fracice',idnc,iarch,local,.true.)
     
! DIAGNOSTICS -------------------------------------------------
lwrite=(ktau>0)
call histwrt3(u10,'u10',idnc,iarch,local,.true.)
call histwrt3(cape_max,'cape_max',idnc,iarch,local,lwrite)
call histwrt3(cape_ave,'cape_ave',idnc,iarch,local,lwrite)
      
if ( itype/=-1 ) then  ! these not written to restart file
  aa=rndmax(:)*86400./dt ! scale up to mm/day
  call histwrt3(aa,'maxrnd',idnc,iarch,local,lday)
  call histwrt3(tmaxscr,'tmaxscr',idnc,iarch,local,lday)
  call histwrt3(tminscr,'tminscr',idnc,iarch,local,lday)
  call histwrt3(rhmaxscr,'rhmaxscr',idnc,iarch,local,lday)
  call histwrt3(rhminscr,'rhminscr',idnc,iarch,local,lday)
  call histwrt3(u10max,'u10max',idnc,iarch,local,lday)
  call histwrt3(v10max,'v10max',idnc,iarch,local,lday)
  call histwrt3(u10mx,'sfcwindmax',idnc,iarch,local,lave)
  call histwrt3(u1max,'u1max',idnc,iarch,local,lday)
  call histwrt3(v1max,'v1max',idnc,iarch,local,lday)
  call histwrt3(u2max,'u2max',idnc,iarch,local,lday)
  call histwrt3(v2max,'v2max',idnc,iarch,local,lday)
  ! if writes done more than once per day, 
  ! needed to augment accumulated 3-hourly rainfall in rnd06 to rnd21 
  ! to allow for intermediate zeroing of precip()
  ! but not needed from 17/9/03 with introduction of rnd24
  if (l3hr) then
    call histwrt3(rnd_3hr(1,1),'rnd03',idnc,iarch,local,lday)
    call histwrt3(rnd_3hr(1,2),'rnd06',idnc,iarch,local,lday)
    call histwrt3(rnd_3hr(1,3),'rnd09',idnc,iarch,local,lday)
    call histwrt3(rnd_3hr(1,4),'rnd12',idnc,iarch,local,lday)
    call histwrt3(rnd_3hr(1,5),'rnd15',idnc,iarch,local,lday)
    call histwrt3(rnd_3hr(1,6),'rnd18',idnc,iarch,local,lday)
    call histwrt3(rnd_3hr(1,7),'rnd21',idnc,iarch,local,lday)
  end if
  call histwrt3(rnd_3hr(1,8),'rnd24',idnc,iarch,local,lday)
  if ( nextout>=2 .and. l3hr ) then ! 6-hourly u10 & v10
    call histwrt3( u10_3hr(1,2), 'u10_06',idnc,iarch,local,lday)
    call histwrt3( v10_3hr(1,2), 'v10_06',idnc,iarch,local,lday)
    call histwrt3( u10_3hr(1,4), 'u10_12',idnc,iarch,local,lday)
    call histwrt3( v10_3hr(1,4), 'v10_12',idnc,iarch,local,lday)
    call histwrt3( u10_3hr(1,6), 'u10_18',idnc,iarch,local,lday)
    call histwrt3( v10_3hr(1,6), 'v10_18',idnc,iarch,local,lday)
    call histwrt3( u10_3hr(1,8), 'u10_24',idnc,iarch,local,lday)
    call histwrt3( v10_3hr(1,8), 'v10_24',idnc,iarch,local,lday)
    call histwrt3(tscr_3hr(1,2),'tscr_06',idnc,iarch,local,lday)
    call histwrt3(tscr_3hr(1,4),'tscr_12',idnc,iarch,local,lday)
    call histwrt3(tscr_3hr(1,6),'tscr_18',idnc,iarch,local,lday)
    call histwrt3(tscr_3hr(1,8),'tscr_24',idnc,iarch,local,lday)
    call histwrt3( rh1_3hr(1,2), 'rh1_06',idnc,iarch,local,lday)
    call histwrt3( rh1_3hr(1,4), 'rh1_12',idnc,iarch,local,lday)
    call histwrt3( rh1_3hr(1,6), 'rh1_18',idnc,iarch,local,lday)
    call histwrt3( rh1_3hr(1,8), 'rh1_24',idnc,iarch,local,lday)
  endif  ! (nextout>=2)
  if ( nextout>=3 .and. l3hr ) then  ! also 3-hourly u10 & v10
    call histwrt3(tscr_3hr(1,1),'tscr_03',idnc,iarch,local,lday)
    call histwrt3(tscr_3hr(1,3),'tscr_09',idnc,iarch,local,lday)
    call histwrt3(tscr_3hr(1,5),'tscr_15',idnc,iarch,local,lday)
    call histwrt3(tscr_3hr(1,7),'tscr_21',idnc,iarch,local,lday)
    call histwrt3( rh1_3hr(1,1), 'rh1_03',idnc,iarch,local,lday)
    call histwrt3( rh1_3hr(1,3), 'rh1_09',idnc,iarch,local,lday)
    call histwrt3( rh1_3hr(1,5), 'rh1_15',idnc,iarch,local,lday)
    call histwrt3( rh1_3hr(1,7), 'rh1_21',idnc,iarch,local,lday)
    call histwrt3( u10_3hr(1,1), 'u10_03',idnc,iarch,local,lday)
    call histwrt3( v10_3hr(1,1), 'v10_03',idnc,iarch,local,lday)
    call histwrt3( u10_3hr(1,3), 'u10_09',idnc,iarch,local,lday)
    call histwrt3( v10_3hr(1,3), 'v10_09',idnc,iarch,local,lday)
    call histwrt3( u10_3hr(1,5), 'u10_15',idnc,iarch,local,lday)
    call histwrt3( v10_3hr(1,5), 'v10_15',idnc,iarch,local,lday)
    call histwrt3( u10_3hr(1,7), 'u10_21',idnc,iarch,local,lday)
    call histwrt3( v10_3hr(1,7), 'v10_21',idnc,iarch,local,lday)
  endif  ! nextout>=3
  if ( nextout>=4 .and. nllp==3 ) then  
    do k=1,klt
      do iq=1,ilt*jlt        
        tr(iq,k,ngas+1)=tr(iq,k,ngas+1)-rlatt(iq)*180./pi
        tr(iq,k,ngas+2)=tr(iq,k,ngas+2)-rlongg(iq)*180./pi
        if(tr(iq,k,ngas+2)>180.)tr(iq,k,ngas+2)=tr(iq,k,ngas+2)-360.
        if(tr(iq,k,ngas+2)<-180.)tr(iq,k,ngas+2)=tr(iq,k,ngas+2)+360.
        tr(iq,k,ngas+3)=tr(iq,k,ngas+3)-.01*ps(iq)*sig(k)  ! in hPa
      enddo
    enddo
!   N.B. does not yet properly handle across Grenwich Meridion
    tmpry=tr(1:ifull,:,ngas+1)
    call histwrt4(tmpry,'del_lat',idnc,iarch,local,.true.)
    tmpry=tr(1:ifull,:,ngas+2)
    call histwrt4(tmpry,'del_lon',idnc,iarch,local,.true.)
    tmpry=tr(1:ifull,:,ngas+3)
    call histwrt4(tmpry,'del_p',idnc,iarch,local,.true.)
  endif  ! (nextout>=4.and.nllp==3)
  ! only write these once per avg period
  call histwrt3(tscr_ave,'tscr_ave',idnc,iarch,local,lave)
  call histwrt3(cbas_ave,'cbas_ave',idnc,iarch,local,lave)
  call histwrt3(ctop_ave,'ctop_ave',idnc,iarch,local,lave)
  call histwrt3(dew_ave,'dew_ave',idnc,iarch,local,lave)
  call histwrt3(evap,'evap',idnc,iarch,local,lave)
  call histwrt3(epan_ave,'epan_ave',idnc,iarch,local,lave)
  call histwrt3(epot_ave,'epot_ave',idnc,iarch,local,lave)
  call histwrt3(eg_ave,'eg_ave',idnc,iarch,local,lave)
  call histwrt3(fg_ave,'fg_ave',idnc,iarch,local,lave)
  call histwrt3(rnet_ave,'rnet_ave',idnc,iarch,local,lave)
  call histwrt3(ga_ave,'ga_ave',idnc,iarch,local,lave)
  call histwrt3(riwp_ave,'iwp_ave',idnc,iarch,local,lave)
  call histwrt3(rlwp_ave,'lwp_ave',idnc,iarch,local,lave)
  call histwrt3(cll_ave,'cll',idnc,iarch,local,lrad)
  call histwrt3(clm_ave,'clm',idnc,iarch,local,lrad)
  call histwrt3(clh_ave,'clh',idnc,iarch,local,lrad)
  call histwrt3(cld_ave,'cld',idnc,iarch,local,lrad)
  call histwrt3(wb_ave(:,1),'wb1_ave',idnc,iarch,local,lave)
  call histwrt3(wb_ave(:,2),'wb2_ave',idnc,iarch,local,lave)
  call histwrt3(wb_ave(:,3),'wb3_ave',idnc,iarch,local,lave)
  call histwrt3(wb_ave(:,4),'wb4_ave',idnc,iarch,local,lave)
  call histwrt3(wb_ave(:,5),'wb5_ave',idnc,iarch,local,lave)
  call histwrt3(wb_ave(:,6),'wb6_ave',idnc,iarch,local,lave)
  call histwrt3(tsu_ave,'tsu_ave',idnc,iarch,local,lave)
  call histwrt3(alb_ave,'alb_ave',idnc,iarch,local,lrad)
  call histwrt3(psl_ave,'pmsl_ave',idnc,iarch,local,lave)
  if ( nmlo/=0 ) then
    call histwrt3(mixdep_ave,'mixd_ave',idnc,iarch,local,lave)
  end if
  lwrite = ktau>0
  call histwrt3(tscrn,'tscrn',idnc,iarch,local,lwrite)
  call histwrt3(qgscrn,'qgscrn',idnc,iarch,local,lwrite)
  call histwrt3(rhscrn,'rhscrn',idnc,iarch,local,lwrite)
  call histwrt3(uscrn,'uscrn',idnc,iarch,local,lwrite)
  call histwrt3(rnet,'rnet',idnc,iarch,local,lwrite)
  call histwrt3(epan,'epan',idnc,iarch,local,lwrite)
  call histwrt3(eg,'eg',idnc,iarch,local,lwrite)
  call histwrt3(fg,'fg',idnc,iarch,local,lwrite)
  call histwrt3(taux,'taux',idnc,iarch,local,lwrite)
  call histwrt3(tauy,'tauy',idnc,iarch,local,lwrite)
  ! "extra" outputs
  if ( nextout>=1 ) then
    call histwrt3(rtu_ave,'rtu_ave',idnc,iarch,local,lrad)
    call histwrt3(rtc_ave,'rtc_ave',idnc,iarch,local,lrad)
    call histwrt3(rgdn_ave,'rgdn_ave',idnc,iarch,local,lrad)
    call histwrt3(rgn_ave,'rgn_ave',idnc,iarch,local,lrad)
    call histwrt3(rgc_ave,'rgc_ave',idnc,iarch,local,lrad)
    call histwrt3(sint_ave,'sint_ave',idnc,iarch,local,lrad)
    call histwrt3(sot_ave,'sot_ave',idnc,iarch,local,lrad)
    call histwrt3(soc_ave,'soc_ave',idnc,iarch,local,lrad)
    call histwrt3(sgdn_ave,'sgdn_ave',idnc,iarch,local,lrad)
    call histwrt3(sgn_ave,'sgn_ave',idnc,iarch,local,lave)
    call histwrt3(sgc_ave,'sgc_ave',idnc,iarch,local,lrad)
    aa=sunhours/3600.
    call histwrt3(aa,'sunhours',idnc,iarch,local,lave)
    call histwrt3(fbeam_ave,'fbeam_ave',idnc,iarch,local,lrad)
    lwrite=(ktau>0)
    call histwrt3(dpsdt,'dpsdt',idnc,iarch,local,lwrite)
    call histwrt3(ustar,'ustar',idnc,iarch,local,lwrite)
  endif   ! nextout>=1
endif    ! (ktau>0.and.itype/=-1)
      
! TURBULENT MIXING --------------------------------------------
if ( nextout>=1 .or. (nvmix==6.and.itype==-1) ) then
  call histwrt3(pblh,'pblh',idnc,iarch,local,.true.)
  if ( nvmix==6 ) then
    call histwrt3(zidry,'dpblh',idnc,iarch,local,.true.)
  end if
end if

! AEROSOL OPTICAL DEPTH ---------------------------------------
if ( nextout>=1 .and. abs(iaero)>=2 .and. nrad==5 ) then
  lwrite=(ktau>0)
  call histwrt3(opticaldepth(:,1,1),'sdust_vis',idnc,iarch,local,lwrite)
  !call histwrt3(opticaldepth(:,1,2),'sdust_nir',idnc,iarch,local,lwrite)
  !call histwrt3(opticaldepth(:,1,3),'sdust_lw',idnc,iarch,local,lwrite)
  call histwrt3(opticaldepth(:,2,1),'ldust_vis',idnc,iarch,local,lwrite)
  !call histwrt3(opticaldepth(:,2,2),'ldust_nir',idnc,iarch,local,lwrite)
  !call histwrt3(opticaldepth(:,2,3),'ldust_lw',idnc,iarch,local,lwrite)
  call histwrt3(opticaldepth(:,3,1),'so4_vis',idnc,iarch,local,lwrite)
  !call histwrt3(opticaldepth(:,3,2),'so4_nir',idnc,iarch,local,lwrite)
  !call histwrt3(opticaldepth(:,3,3),'so4_lw',idnc,iarch,local,lwrite)
  call histwrt3(opticaldepth(:,4,1),'aero_vis',idnc,iarch,local,lwrite)
  !call histwrt3(opticaldepth(:,4,2),'aero_nir',idnc,iarch,local,lwrite)
  !call histwrt3(opticaldepth(:,4,3),'aero_lw',idnc,iarch,local,lwrite)
  call histwrt3(opticaldepth(:,5,1),'bc_vis',idnc,iarch,local,lwrite)
  !call histwrt3(opticaldepth(:,5,2),'bc_nir',idnc,iarch,local,lwrite)
  !call histwrt3(opticaldepth(:,5,3),'bc_lw',idnc,iarch,local,lwrite)
  call histwrt3(opticaldepth(:,6,1),'oc_vis',idnc,iarch,local,lwrite)
  !call histwrt3(opticaldepth(:,6,2),'oc_nir',idnc,iarch,local,lwrite)
  !call histwrt3(opticaldepth(:,6,3),'oc_lw',idnc,iarch,local,lwrite)
  call histwrt3(opticaldepth(:,7,1),'ssalt_vis',idnc,iarch,local,lwrite)
  !call histwrt3(opticaldepth(:,7,2),'ssalt_nir',idnc,iarch,local,lwrite)
  !call histwrt3(opticaldepth(:,7,3),'ssalt_lw',idnc,iarch,local,lwrite)
  aa=max(duste*3.154e10,0.) ! g/m2/yr
  call histwrt3(aa,'duste_ave',idnc,iarch,local,lave)
  aa=max(dustdd*3.154e10,0.) ! g/m2/yr
  call histwrt3(aa,'dustdd_ave',idnc,iarch,local,lave)
  aa=max(dustwd*3.154e10,0.) ! g/m2/yr
  call histwrt3(aa,'dustwd_ave',idnc,iarch,local,lave)
  aa=max(dust_burden*1.e6,0.) ! mg/m2
  call histwrt3(aa,'dustb_ave',idnc,iarch,local,lave)
  aa=max(bce*3.154e10,0.) ! g/m2/yr
  call histwrt3(aa,'bce_ave',idnc,iarch,local,lave)
  aa=max(bcdd*3.154e10,0.) ! g/m2/yr
  call histwrt3(aa,'bcdd_ave',idnc,iarch,local,lave)
  aa=max(bcwd*3.154e10,0.) ! g/m2/yr
  call histwrt3(aa,'bcwd_ave',idnc,iarch,local,lave)
  aa=max(bc_burden*1.e6,0.) ! mg/m2
  call histwrt3(aa,'bcb_ave',idnc,iarch,local,lave)
  aa=max(oce*3.154e10,0.) ! g/m2/yr
  call histwrt3(aa,'oce_ave',idnc,iarch,local,lave)
  aa=max(ocdd*3.154e10,0.) ! g/m2/yr
  call histwrt3(aa,'ocdd_ave',idnc,iarch,local,lave)
  aa=max(ocwd*3.154e10,0.) ! g/m2/yr
  call histwrt3(aa,'ocwd_ave',idnc,iarch,local,lave)
  aa=max(oc_burden*1.e6,0.) ! mg/m2
  call histwrt3(aa,'ocb_ave',idnc,iarch,local,lave)
  aa=max(dmse*3.154e10,0.) ! gS/m2/yr (*1.938 for g/m2/yr)
  call histwrt3(aa,'dmse_ave',idnc,iarch,local,lave)
  aa=max(dmsso2o*3.154e10,0.) ! gS/m2/yr
  call histwrt3(aa,'dmsso2_ave',idnc,iarch,local,lave)
  aa=max(so2e*3.154e10,0.) ! gS/m2/yr (*2. for g/m2/yr)
  call histwrt3(aa,'so2e_ave',idnc,iarch,local,lave)
  aa=max(so2so4o*3.154e10,0.) ! gS/m2/yr
  call histwrt3(aa,'so2so4_ave',idnc,iarch,local,lave)
  aa=max(so2dd*3.154e10,0.) ! gS/m2/yr (*2. for g/m2/yr)
  call histwrt3(aa,'so2dd_ave',idnc,iarch,local,lave)
  aa=max(so2wd*3.154e10,0.) ! gS/m2/yr (*2. for g/m2/yr)
  call histwrt3(aa,'so2wd_ave',idnc,iarch,local,lave)
  aa=max(so4e*3.154e10,0.) ! gS/m2/yr (*3. for g/m2/yr)
  call histwrt3(aa,'so4e_ave',idnc,iarch,local,lave)
  aa=max(so4dd*3.154e10,0.) ! gS/m2/yr (*3. for g/m2/yr)
  call histwrt3(aa,'so4dd_ave',idnc,iarch,local,lave)
  aa=max(so4wd*3.154e10,0.) ! gS/m2/yr (*3. for g/m2/yr)
  call histwrt3(aa,'so4wd_ave',idnc,iarch,local,lave)
  aa=max(dms_burden*1.e6,0.) ! mgS/m2
  call histwrt3(aa,'dmsb_ave',idnc,iarch,local,lave)
  aa=max(so2_burden*1.e6,0.) ! mgS/m2
  call histwrt3(aa,'so2b_ave',idnc,iarch,local,lave)
  aa=max(so4_burden*1.e6,0.) ! mgS/m2
  call histwrt3(aa,'so4b_ave',idnc,iarch,local,lave)
end if

! CABLE -------------------------------------------------------
if ( nsib==6 .or. nsib==7 ) then
  if ( nextout>=1 .or. itype==-1 ) then
    if ( ccycle==0 ) then
      !call histwrt3(cplant(:,1),'cplant1',idnc,iarch,local,.true.)
      !call histwrt3(cplant(:,2),'cplant2',idnc,iarch,local,.true.)
      !call histwrt3(cplant(:,3),'cplant3',idnc,iarch,local,.true.)
      !call histwrt3(csoil(:,1),'csoil1',idnc,iarch,local,.true.)
      !call histwrt3(csoil(:,2),'csoil2',idnc,iarch,local,.true.)
    else
      lwrite=mod(ktau,nperday)==0.or.ktau==ntau ! only write once per day
      do k=1,mplant
        write(vname,'("cplant",I1.1)') k
        call histwrt3(cplant(:,k),vname,idnc,iarch,local,lwrite)
        write(vname,'("nplant",I1.1)') k
        call histwrt3(niplant(:,k),vname,idnc,iarch,local,lwrite)
        write(vname,'("pplant",I1.1)') k
        call histwrt3(pplant(:,k),vname,idnc,iarch,local,lwrite)
      end do
      do k=1,mlitter
        write(vname,'("clitter",I1.1)') k
        call histwrt3(clitter(:,k),vname,idnc,iarch,local,lwrite)
        write(vname,'("nlitter",I1.1)') k
        call histwrt3(nilitter(:,k),vname,idnc,iarch,local,lwrite)
        write(vname,'("plitter",I1.1)') k
        call histwrt3(plitter(:,k),vname,idnc,iarch,local,lwrite)
      end do
      do k=1,msoil
        write(vname,'("csoil",I1.1)') k
        call histwrt3(csoil(:,k),vname,idnc,iarch,local,lwrite)
        write(vname,'("nsoil",I1.1)') k
        call histwrt3(nisoil(:,k),vname,idnc,iarch,local,lwrite)
        write(vname,'("psoil",I1.1)') k
        call histwrt3(psoil(:,k),vname,idnc,iarch,local,lwrite)
      end do
      call histwrt3(glai,'glai',idnc,iarch,local,lwrite)
    end if
  end if
  if ( nextout>=1 .and. itype/=-1 ) then
    aa=fpn_ave+frp_ave+frs_ave
    call histwrt3(aa,'fnee_ave',idnc,iarch,local,lave)
    call histwrt3(fpn_ave,'fpn_ave',idnc,iarch,local,lave)
    call histwrt3(frp_ave,'frp_ave',idnc,iarch,local,lave)
    call histwrt3(frs_ave,'frs_ave',idnc,iarch,local,lave)
  end if
endif   

! URBAN -------------------------------------------------------
if ( nurban<=-1 .or. (nurban>=1.and.itype==-1) ) then
  atebdwn(:,:)=999. ! must be the same as spval in onthefly.f
  call atebsave(atebdwn,0,rawtemp=.true.)
  do k = 1,20
    where ( atebdwn(:,k)<100. .and. itype==1 )
      atebdwn(:,k) = atebdwn(:,k) + urbtemp ! Allows urban temperatures to use a 290K offset
    end where
  end do
  call histwrt3(atebdwn(:,1),'rooftgg1',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,2),'rooftgg2',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,3),'rooftgg3',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,4),'rooftgg4',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,5),'rooftgg5',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,6),'waletgg1',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,7),'waletgg2',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,8),'waletgg3',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,9),'waletgg4',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,10),'waletgg5',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,11),'walwtgg1',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,12),'walwtgg2',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,13),'walwtgg3',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,14),'walwtgg4',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,15),'walwtgg5',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,16),'roadtgg1',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,17),'roadtgg2',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,18),'roadtgg3',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,19),'roadtgg4',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,20),'roadtgg5',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,21),'urbnsmc',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,22),'urbnsmr',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,23),'roofwtr',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,24),'roadwtr',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,25),'urbwtrc',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,26),'urbwtrr',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,27),'roofsnd',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,28),'roadsnd',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,29),'roofden',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,30),'roadden',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,31),'roofsna',idnc,iarch,local,.true.)
  call histwrt3(atebdwn(:,32),'roadsna',idnc,iarch,local,.true.)
end if

! **************************************************************
! WRITE 4D VARIABLES (3D + Time)
! **************************************************************

! ATMOSPHERE DYNAMICS ------------------------------------------
lwrite = (ktau>0)
call histwrt4(t,'temp',idnc,iarch,local,.true.)
call histwrt4(u,'u',idnc,iarch,local,.true.)
call histwrt4(v,'v',idnc,iarch,local,.true.)
do k = 1,kl
  tmpry(1:ifull,k)=ps(1:ifull)*dpsldt(1:ifull,k)
enddo
call histwrt4(tmpry,'omega',idnc,iarch,local,lwrite)
call histwrt4(qg,'mixr',idnc,iarch,local,.true.)
lwrite = (mod(ktau,nperavg)==0.or.ktau==ntau).and.(ktau>0)
call histwrt4(convh_ave,'convh_ave',idnc,iarch,local,lwrite)
      
! MICROPHYSICS ------------------------------------------------
if ( ldr/=0 ) then
  call histwrt4(qfg,'qfg',idnc,iarch,local,.true.)
  call histwrt4(qlg,'qlg',idnc,iarch,local,.true.)
  if ( ncloud>=2 ) then
    call histwrt4(qrg,'qrg',idnc,iarch,local,.true.)
  end if
  if ( ncloud>=3 ) then
    call histwrt4(qsng,'qsng',idnc,iarch,local,.true.)
    call histwrt4(qgrg,'qgrg',idnc,iarch,local,.true.)
  end if
  call histwrt4(cfrac,'cfrac',idnc,iarch,local,.true.)
  if ( ncloud>=2 ) then
    call histwrt4(rfrac,'rfrac',idnc,iarch,local,.true.)
  end if
  if ( ncloud>=3 ) then
    call histwrt4(sfrac,'sfrac',idnc,iarch,local,.true.)
    call histwrt4(gfrac,'gfrac',idnc,iarch,local,.true.)
  end if
  if ( ncloud>=4 ) then
    call histwrt4(stratcloud,'stratcf',idnc,iarch,local,.true.)  
    if ( itype==-1 ) then
      call histwrt4(nettend,'strat_nt',idnc,iarch,local,.true.)
    end if
  end if
endif
      
! TURBULENT MIXING --------------------------------------------
if ( nvmix==6 .and. (nextout>=1.or.itype==-1) ) then
  call histwrt4(tke,'tke',idnc,iarch,local,.true.)
  call histwrt4(eps,'eps',idnc,iarch,local,.true.)
end if

! TRACERS -----------------------------------------------------
if ( ngas>0 ) then
  if ( itype==-1 ) then ! restart
    do igas = 1,ngas
      write(trnum,'(i3.3)') igas
      call histwrt4(tr(:,:,igas),    'tr'//trnum,  idnc,iarch,local,.true.)
    enddo ! igas loop
  else                  ! history
    do igas = 1,ngas
      write(trnum,'(i3.3)') igas
      !call histwrt4(tr(:,:,igas),    'tr'//trnum,  idnc,iarch,local,.true.)
      call histwrt4(traver(:,:,igas),'trav'//trnum,idnc,iarch,local,lave)
      ! rml 14/5/10 option to write out local time afternoon average
      if ( writetrpm ) then
        ! first divide by number of contributions to average
        do k = 1,klt
          trpm(1:ifull,k,igas) = trpm(1:ifull,k,igas)/float(npm)
        end do
        call histwrt4(trpm(:,:,igas),'trpm'//trnum,idnc,iarch,local,.true.)
      endif
    enddo ! igas loop
    ! reset arrays
    if ( writetrpm ) then
      trpm = 0.
      npm  = 0
    endif
  end if
endif  ! (ngasc>0)

! AEROSOLS ----------------------------------------------------
if ( abs(iaero)>=2 ) then
  call histwrt4(xtg(:,:,1), 'dms',     idnc,iarch,local,.true.)
  call histwrt4(xtg(:,:,2), 'so2',     idnc,iarch,local,.true.)
  call histwrt4(xtg(:,:,3), 'so4',     idnc,iarch,local,.true.)
  call histwrt4(xtg(:,:,4), 'bco',     idnc,iarch,local,.true.)
  call histwrt4(xtg(:,:,5), 'bci',     idnc,iarch,local,.true.)
  call histwrt4(xtg(:,:,6), 'oco',     idnc,iarch,local,.true.)
  call histwrt4(xtg(:,:,7), 'oci',     idnc,iarch,local,.true.)
  call histwrt4(xtg(:,:,8), 'dust1',   idnc,iarch,local,.true.)
  call histwrt4(xtg(:,:,9), 'dust2',   idnc,iarch,local,.true.)
  call histwrt4(xtg(:,:,10),'dust3',   idnc,iarch,local,.true.)
  call histwrt4(xtg(:,:,11),'dust4',   idnc,iarch,local,.true.)
  call histwrt4(ssn(:,:,1), 'seasalt1',idnc,iarch,local,.true.)
  call histwrt4(ssn(:,:,2), 'seasalt2',idnc,iarch,local,.true.)
  if ( iaero<=-2 ) then
    do k = 1,kl
      qtot(:)   = qg(1:ifull,k) + qlg(1:ifull,k) + qrg(1:ifull,k)    &
                + qfg(1:ifull,k) + qsng(1:ifull,k) + qgrg(1:ifull,k)
      tv(:)     = t(1:ifull,k)*(1.+1.61*qg(1:ifull,k)-qtot(:))   ! virtual temperature
      rhoa(:,k) = ps(1:ifull)*sig(k)/(rdry*tv(:))                !density of air
    end do
    call aerodrop(1,ifull,tmpry,rhoa)
    call histwrt4(tmpry,'cdn',idnc,iarch,local,.true.)
  end if
end if

!**************************************************************
! RESTART ONLY DATA
!**************************************************************

if ( itype==-1 ) then
  call histwrt4(dpsldt,    'dpsldt',idnc,iarch,local,.true.)
  call histwrt4(phi_nh,    'zgnhs', idnc,iarch,local,.true.)
  call histwrt4(sdot(:,2:),'sdot',  idnc,iarch,local,.true.)
  call histwrt4(pslx,      'pslx',  idnc,iarch,local,.true.)
  call histwrt4(savu,      'savu',  idnc,iarch,local,.true.)
  call histwrt4(savv,      'savv',  idnc,iarch,local,.true.)
  call histwrt4(savu1,     'savu1', idnc,iarch,local,.true.)
  call histwrt4(savv1,     'savv1', idnc,iarch,local,.true.)
  call histwrt4(savu2,     'savu2', idnc,iarch,local,.true.)
  call histwrt4(savv2,     'savv2', idnc,iarch,local,.true.)
  if ( abs(nmlo)>=3 .and. abs(nmlo)<=9 ) then
    do k = 1,wlev
      write(vname,'("oldu1",I2.2)') k
      call histwrt3(oldu1(:,k),vname,idnc,iarch,local,.true.)
      write(vname,'("oldv1",I2.2)') k
      call histwrt3(oldv1(:,k),vname,idnc,iarch,local,.true.)
      write(vname,'("oldu2",I2.2)') k
      call histwrt3(oldu2(:,k),vname,idnc,iarch,local,.true.)
      write(vname,'("oldv2",I2.2)') k
      call histwrt3(oldv2(:,k),vname,idnc,iarch,local,.true.)
    end do
    call histwrt3(ipice,'ipice',idnc,iarch,local,.true.)
  end if
  call histwrt3(wbice(1,1),'wbice1',idnc,iarch,local,.true.)
  call histwrt3(wbice(1,2),'wbice2',idnc,iarch,local,.true.)
  call histwrt3(wbice(1,3),'wbice3',idnc,iarch,local,.true.)
  call histwrt3(wbice(1,4),'wbice4',idnc,iarch,local,.true.)
  call histwrt3(wbice(1,5),'wbice5',idnc,iarch,local,.true.)
  call histwrt3(wbice(1,6),'wbice6',idnc,iarch,local,.true.)
  if ( nmlo==0 ) then ! otherwise already written above
    call histwrt3(tggsn(1,1),'tggsn1',idnc,iarch,local,.true.)
    call histwrt3(tggsn(1,2),'tggsn2',idnc,iarch,local,.true.)
    call histwrt3(tggsn(1,3),'tggsn3',idnc,iarch,local,.true.)
  end if
  call histwrt3(smass(1,1),'smass1',idnc,iarch,local,.true.)
  call histwrt3(smass(1,2),'smass2',idnc,iarch,local,.true.)
  call histwrt3(smass(1,3),'smass3',idnc,iarch,local,.true.)
  call histwrt3(ssdn(1,1), 'ssdn1', idnc,iarch,local,.true.)
  call histwrt3(ssdn(1,2), 'ssdn2', idnc,iarch,local,.true.)
  call histwrt3(ssdn(1,3), 'ssdn3', idnc,iarch,local,.true.)
  call histwrt3(snage,     'snage', idnc,iarch,local,.true.)
  aa(:) = isflag(:)
  call histwrt3(aa,    'sflag', idnc,iarch,local,.true.)
  call histwrt3(sgsave,'sgsave',idnc,iarch,local,.true.)       
  if ( nsib==6 .or. nsib==7 ) then
    call savetile(idnc,local,iarch)
  end if
endif  ! (itype==-1)

if ( myid==0 .or. local ) then
  call ccnf_sync(idnc)
end if

if ( myid==0 ) then
  write(6,*) "finished writing to ofile"    
end if

return
end subroutine openhist

!--------------------------------------------------------------
! HIGH FREQUENCY OUTPUT FILES
      
subroutine freqfile

use arrays_m                          ! Atmosphere dyamics prognostic arrays
use cc_mpi                            ! CC MPI routines
use infile                            ! Input file routines
use morepbl_m                         ! Additional boundary layer diagnostics
use parmhdff_m                        ! Horizontal diffusion parameters
use screen_m                          ! Screen level diagnostics
use sigs_m                            ! Atmosphere sigma levels
use tracers_m                         ! Tracer data
      
implicit none

include 'newmpar.h'                   ! Grid parameters
include 'dates.h'                     ! Date data
include 'filnames.h'                  ! Filenames
include 'kuocom.h'                    ! Convection parameters
include 'parm.h'                      ! Model configuration
include 'parmdyn.h'                   ! Dynamics parameters
include 'parmgeom.h'                  ! Coordinate data
include 'parmhor.h'                   ! Horizontal advection parameters

integer leap
common/leap_yr/leap                   ! Leap year (1 to allow leap years)
      
integer, parameter :: freqvars = 8  ! number of variables to write
integer, parameter :: nihead   = 54
integer, parameter :: nrhead   = 14
integer, dimension(nihead) :: nahead
integer, dimension(tblock) :: datedat
integer, dimension(4) :: adim
integer, dimension(3) :: sdim
integer, dimension(1) :: start,ncount
integer ixp,iyp,izp,tlen
integer icy,icm,icd,ich,icmi,ics,ti
integer i,j,n,fiarch
integer, save :: fncid = -1
integer, save :: idnt = 0
integer, save :: idkdate = 0
integer, save :: idktime = 0
integer, save :: idmtimer = 0
real, dimension(:,:,:), allocatable, save :: freqstore
real, dimension(ifull) :: umag, pmsl
real, dimension(il_g) :: xpnt
real, dimension(jl_g) :: ypnt
real, dimension(1) :: zpnt
real, dimension(nrhead) :: ahead
real(kind=8), dimension(tblock) :: tpnt
logical, save :: first = .true.
character(len=180) :: ffile
character(len=40) :: lname
character(len=33) :: grdtim
character(len=20) :: timorg

call START_LOG(outfile_begin)

! allocate arrays and open new file
if ( first ) then
  if ( myid==0 ) then
    write(6,*) "Initialise high frequency output"
  end if
  allocate(freqstore(ifull,tblock,freqvars))
  freqstore(:,:,:) = 0.
  if ( localhist ) then
    write(ffile,"(a,'.',i6.6)") trim(surfile), myid
  else
    ffile=surfile
  end if
  if ( myid==0 .or. localhist ) then
    call ccnf_create(ffile,fncid)
    ! Turn off the data filling
    call ccnf_nofill(fncid)
    ! Create dimensions
    if ( localhist ) then
      call ccnf_def_dim(fncid,'longitude',il,adim(1))
      call ccnf_def_dim(fncid,'latitude',jl,adim(2))
    else
      call ccnf_def_dim(fncid,'longitude',il_g,adim(1))
      call ccnf_def_dim(fncid,'latitude',jl_g,adim(2))
    endif
    call ccnf_def_dim(fncid,'lev',1,adim(3))
    if ( unlimitedhist ) then
      call ccnf_def_dimu(fncid,'time',adim(4))
    else
      tlen = ntau
      call ccnf_def_dim(fncid,'time',tlen,adim(4))  
    end if
    ! Define coords.
    call ccnf_def_var(fncid,'longitude','float',1,adim(1:1),ixp)
    call ccnf_put_att(fncid,ixp,'point_spacing','even')
    call ccnf_put_att(fncid,ixp,'units','degrees_east')
    call ccnf_def_var(fncid,'latitude','float',1,adim(2:2),iyp)
    call ccnf_put_att(fncid,iyp,'point_spacing','even')
    call ccnf_put_att(fncid,iyp,'units','degrees_north')
    call ccnf_def_var(fncid,'lev','float',1,adim(3:3),izp)
    call ccnf_put_att(fncid,izp,'positive','down')
    call ccnf_put_att(fncid,izp,'point_spacing','uneven')
    call ccnf_put_att(fncid,izp,'units','sigma_level')
    call ccnf_def_var(fncid,'time','double',1,adim(4:4),idnt)
    call ccnf_put_att(fncid,idnt,'point_spacing','even')
    icy=kdate/10000
    icm=max(1,min(12,(kdate-icy*10000)/100))
    icd=max(1,min(31,(kdate-icy*10000-icm*100)))
    if ( icy<100 ) then
      icy=icy+1900
    end if
    ich=ktime/100
    icmi=(ktime-ich*100)
    ics=0
    write(timorg,'(i2.2,"-",a3,"-",i4.4,3(":",i2.2))') icd,month(icm),icy,ich,icmi,ics
    call ccnf_put_att(fncid,idnt,'time_origin',timorg)
    write(grdtim,'("seconds since ",i4.4,"-",i2.2,"-",i2.2," ",2(i2.2,":"),i2.2)') icy,icm,icd,ich,icmi,ics
    call ccnf_put_att(fncid,idnt,'units',grdtim)
    if ( leap==0 ) then
      call ccnf_put_att(fncid,idnt,'calendar','noleap')
    end if
    call ccnf_def_var(fncid,'kdate','int',1,adim(4:4),idkdate)
    call ccnf_def_var(fncid,'ktime','int',1,adim(4:4),idktime)
    call ccnf_def_var(fncid,'mtimer','int',1,adim(4:4),idmtimer)
    ! header data
    ahead(1)=ds
    ahead(2)=0.  !difknbd
    ahead(3)=0.  ! was rhkuo for kuo scheme
    ahead(4)=0.  !du
    ahead(5)=rlong0     ! needed by cc2hist
    ahead(6)=rlat0      ! needed by cc2hist
    ahead(7)=schmidt    ! needed by cc2hist
    ahead(8)=0.  !stl2
    ahead(9)=0.  !relaxt
    ahead(10)=0.  !hourbd
    ahead(11)=tss_sh
    ahead(12)=vmodmin
    ahead(13)=av_vmod
    ahead(14)=epsp
    nahead(1)=il_g       ! needed by cc2hist
    nahead(2)=jl_g       ! needed by cc2hist
    nahead(3)=1          ! needed by cc2hist (turns off 3D fields)
    nahead(4)=5
    nahead(5)=0          ! nsd not used now
    nahead(6)=io_in
    nahead(7)=nbd
    nahead(8)=0          ! not needed now  
    nahead(9)=mex
    nahead(10)=mup
    nahead(11)=2 ! nem
    nahead(12)=mtimer
    nahead(13)=0         ! nmi
    nahead(14)=nint(dt)  ! needed by cc2hist
    nahead(15)=0         ! not needed now 
    nahead(16)=nhor
    nahead(17)=nkuo
    nahead(18)=khdif
    nahead(19)=kl        ! needed by cc2hist (was kwt)
    nahead(20)=0  !iaa
    nahead(21)=0  !jaa
    nahead(22)=-4
    nahead(23)=0       ! not needed now      
    nahead(24)=0  !lbd
    nahead(25)=nrun
    nahead(26)=0
    nahead(27)=khor
    nahead(28)=ksc
    nahead(29)=kountr
    nahead(30)=1 ! ndiur
    nahead(31)=0  ! spare
    nahead(32)=nhorps
    nahead(33)=nsoil
    nahead(34)=ms        ! needed by cc2hist
    nahead(35)=ntsur
    nahead(36)=nrad
    nahead(37)=kuocb
    nahead(38)=nvmix
    nahead(39)=ntsea
    nahead(40)=0  
    nahead(41)=nextout
    nahead(42)=ilt
    nahead(43)=ntrac     ! needed by cc2hist
    nahead(44)=nsib
    nahead(45)=nrungcm
    nahead(46)=ncvmix
    nahead(47)=ngwd
    nahead(48)=lgwd
    nahead(49)=mup
    nahead(50)=nritch_t
    nahead(51)=ldr
    nahead(52)=nevapls
    nahead(53)=nevapcc
    nahead(54)=nt_adv
    call ccnf_put_attg(fncid,'real_header',ahead)
    call ccnf_put_attg(fncid,'int_header',nahead)
    if ( localhist ) then
      call ccnf_put_attg(fncid,'processor_num',myid)
      call ccnf_put_attg(fncid,'nproc',nproc)
#ifdef uniform_decomp
      call ccnf_put_attg(fncid,'decomp','uniform1')
#else
      call ccnf_put_attg(fncid,'decomp','face')
#endif
    endif 
    ! define variables
    sdim(1:2)=adim(1:2)
    sdim(3)=adim(4)
    lname='x-component 10m wind'
    call attrib(fncid,sdim,3,'uas',lname,'m/s',-130.,130.,0,1)
    lname='y-component 10m wind'     
    call attrib(fncid,sdim,3,'vas',lname,'m/s',-130.,130.,0,1)
    lname='Screen temperature'     
    call attrib(fncid,sdim,3,'tscrn',lname,'K',100.,425.,0,1)
    lname='Screen mixing rato'     
    call attrib(fncid,sdim,3,'qgscrn',lname,'kg/kg',0.,.06,0,1)
    lname='Precipitation'
    call attrib(fncid,sdim,3,'rnd',lname,'mm/day',0.,1300.,0,-1)  ! -1=long
    lname='Snowfall'
    call attrib(fncid,sdim,3,'sno',lname,'mm/day',0.,1300.,0,-1)  ! -1=long
    lname='Graupelfall'
    call attrib(fncid,sdim,3,'grpl',lname,'mm/day',0.,1300.,0,-1) ! -1=long
    lname ='Mean sea level pressure'
    call attrib(fncid,sdim,3,'pmsl',lname,'hPa',800.,1200.,0,1)    

    ! end definition mode
    call ccnf_enddef(fncid)
    if ( localhist ) then
      ! Set these to global indices (relative to panel 0 in uniform decomp)
      do i=1,ipan
        xpnt(i) = float(i) + ioff
      end do
      call ccnf_put_vara(fncid,ixp,1,il,xpnt(1:il))
      i=1
      do n=1,npan
        do j=1,jpan
          ypnt(i) = float(j) + joff + (n-noff)*il_g
          i=i+1
        end do
      end do
      call ccnf_put_vara(fncid,iyp,1,jl,ypnt(1:jl))
    else
      do i=1,il_g
        xpnt(i) = float(i)
      end do
      call ccnf_put_vara(fncid,ixp,1,il_g,xpnt(1:il_g))
      do j=1,jl_g
        ypnt(j) = float(j)
      end do
      call ccnf_put_vara(fncid,iyp,1,jl_g,ypnt(1:jl_g))
    end if
    zpnt(1)=1.
    call ccnf_put_vara(fncid,izp,1,1,zpnt(1:1))
  end if
  first=.false.
  if ( myid==0 ) write(6,*) "Finished initialising high frequency output"
end if

! store output
ti = mod(ktau,tblock*tbave)
if ( ti==0 ) ti = tblock*tbave
ti = (ti-1)/tbave + 1
umag = sqrt(u(1:ifull,1)*u(1:ifull,1)+v(1:ifull,1)*v(1:ifull,1))
call mslp(pmsl,psl,zs,t)
freqstore(1:ifull,ti,1) = freqstore(1:ifull,ti,1) + u10*u(1:ifull,1)/max(umag,1.E-6)
freqstore(1:ifull,ti,2) = freqstore(1:ifull,ti,2) + u10*v(1:ifull,1)/max(umag,1.E-6)
freqstore(1:ifull,ti,3) = freqstore(1:ifull,ti,3) + tscrn
freqstore(1:ifull,ti,4) = freqstore(1:ifull,ti,4) + qgscrn
freqstore(1:ifull,ti,5) = freqstore(1:ifull,ti,5) + condx*86400./dt
freqstore(1:ifull,ti,6) = freqstore(1:ifull,ti,6) + conds*86400./dt
freqstore(1:ifull,ti,7) = freqstore(1:ifull,ti,7) + condg*86400./dt
freqstore(1:ifull,ti,8) = freqstore(1:ifull,ti,8) + pmsl/100.

! write data to file
if ( mod(ktau,tblock*tbave)==0 ) then
  if ( myid==0 .or. localhist ) then
    if ( myid==0 ) then
      write(6,*) "Write high frequency output"
    end if
    fiarch = ktau/tbave - tblock + 1
    start(1) = fiarch
    ncount(1) = tblock
    do i = 1,tblock
      tpnt(i)=real(ktau+(i-tblock)*tbave,8)*real(dt,8)
    end do
    call ccnf_put_vara(fncid,idnt,start,ncount,tpnt)
    do i = 1,tblock
      datedat(i) = kdate
    end do
    call ccnf_put_vara(fncid,idkdate,start,ncount,datedat)
    do i = 1,tblock
      datedat(i) = ktime
    end do
    call ccnf_put_vara(fncid,idktime,start,ncount,datedat)
    do i = 1,tblock
      datedat(i) = mtimer + nint(real((i-tblock)*tbave)*dt/60.)
    end do
    call ccnf_put_vara(fncid,idmtimer,start,ncount,datedat)
  end if

  ! record output
  freqstore(:,:,:) = freqstore(:,:,:)/real(tbave)
  call freqwrite(fncid,'uas',   fiarch,tblock,localhist,freqstore(:,:,1))
  call freqwrite(fncid,'vas',   fiarch,tblock,localhist,freqstore(:,:,2))
  call freqwrite(fncid,'tscrn', fiarch,tblock,localhist,freqstore(:,:,3))
  call freqwrite(fncid,'qgscrn',fiarch,tblock,localhist,freqstore(:,:,4))
  call freqwrite(fncid,'rnd',   fiarch,tblock,localhist,freqstore(:,:,5))
  call freqwrite(fncid,'sno',   fiarch,tblock,localhist,freqstore(:,:,6))
  call freqwrite(fncid,'grpl',  fiarch,tblock,localhist,freqstore(:,:,7))
  call freqwrite(fncid,'pmsl',  fiarch,tblock,localhist,freqstore(:,:,8))
  freqstore(:,:,:) = 0.
end if

if ( myid==0 .or. localhist ) then
  ! close file at end of run
  if ( ktau==ntau ) then
    call ccnf_close(fncid)
  elseif ( mod(ktau,tblock*tbave)==0 ) then
    call ccnf_sync(fncid)  
  end if
end if
      
call END_LOG(outfile_end)
      
return
end subroutine freqfile

subroutine mslp(pmsl,psl,zs,t)

use cc_mpi, only : mydiag
use sigs_m

implicit none
! this one will ignore negative zs (i.e. over the ocean)

include 'newmpar.h'
include 'const_phys.h'
include 'parm.h'

integer, parameter :: meth=1 ! 0 for original, 1 for other jlm - always now
integer, save :: lev = -1
real c,conr,con
real, dimension(ifull), intent(out) :: pmsl
real, dimension(ifull), intent(in) :: psl,zs
real, dimension(ifull) :: phi1,tsurf,tav,dlnps
real, dimension(:,:), intent(in) :: t
      
c=grav/stdlapse
conr=c/rdry
if ( lev<0 ) then
  lev=1
  do while (sig(lev+1)<=0.9)
    lev=lev+1
  end do
end if
con=sig(lev)**(rdry/c)/c
      
if ( meth==1 ) then
  phi1(:)=t(1:ifull,lev)*rdry*(1.-sig(lev))/sig(lev) ! phi of sig(lev) above sfce
  tsurf(:)=t(1:ifull,lev)+phi1(:)*stdlapse/grav
  tav(:)=tsurf(:)+zs(1:ifull)*.5*stdlapse/grav
  dlnps(:)=zs(1:ifull)/(rdry*tav(:))
  pmsl(:)=1.e5*exp(psl(:)+dlnps(:))
end if  ! (meth==1)
      
if ( nmaxpr==1 .and. mydiag ) then
  write(6,*) 'meth,lev,sig(lev) ',meth,lev,sig(lev)
  write(6,*) 'zs,t_lev,psl,pmsl ',zs(idjd),t(idjd,lev),psl(idjd),pmsl(idjd)
end if
      
return
end subroutine mslp

end module outcdf
