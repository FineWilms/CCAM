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
    
module trvmix

private
public tracervmix

    contains
    
! ***************************************************************************
! Tracer emission, deposition, settling and turbulent mixing routines
subroutine tracervmix(at,ct)

use arrays_m
use diag_m
use liqwpar_m
use nharrs_m
use pbl_m
use sigs_m
use tracermodule, only : tracunit
use tracers_m 

implicit none

include 'newmpar.h'
include 'const_phys.h'
include 'parm.h'

integer igas, k
real, dimension(ifull,kl) :: updtr
real, intent(in), dimension(ifull,kl) :: at, ct
real, dimension(ifull,kl) :: prf, dz, rhoa, tnhs, tv
real, dimension(ifull,kl) :: trsrc
real molfact, radfact, co2fact, gasfact
logical decay, methloss, mcfloss

! Setup
!trfact = grav * dt / dsig(1)
molfact = 1000.*fair_molm          ! factor for units in mol/m2/s
co2fact = 1000.*fair_molm/fc_molm
radfact = 1.293                    ! test factor for radon units in Bq/m2/s, conc in Bq/m3

tv(:,:) = t(1:ifull,:)*(1.+0.61*qg(1:ifull,:)-qlg(1:ifull,:)-qfg(1:ifull,:) &
                       -qsng(1:ifull,:)-qgrg(1:ifull,:))
tnhs(:,1)=phi_nh(:,1)/bet(1)
do k=2,kl
  ! representing non-hydrostatic term as a correction to air temperature
  tnhs(:,k)=(phi_nh(:,k)-phi_nh(:,k-1)-betm(k)*tnhs(:,k-1))/bet(k)
end do
do k=1,kl
  dz(:,k) = -rdry*dsig(k)*(tv(:,k)+tnhs(:,k))/(grav*sig(k))
  rhoa(:,k) = ps(1:ifull)*sig(k)/(rdry*tv(1:ifull,k)) ! density of air (kg/m**3)
  prf(:,k) = ps(1:ifull)*sig(k)
end do

! Tracer settling
call trsettling(rhoa,t,dz,prf)

do igas=1,ngas                  

  ! Tracer emission
  call trgassflux(igas,trsrc)
  
  ! change gasfact to be depend on tracer flux units
  if (trim(tracunit(igas))=='gC/m2/s') then
    gasfact = co2fact
    decay = .false.
  elseif (trim(tracunit(igas))=='mol/m2/s') then
    gasfact = molfact
    decay = .false.
  elseif (trim(tracunit(igas))=='Bq/m2/s') then
    gasfact = radfact
    decay = .true.
  else
!   assume no surface flux so gasfact could be anything but we'll 
!   set it to zero
    gasfact = 0.
    decay = .false.
  endif
  
  ! also set decay for tracer name 'radon' in case not in Bq/m2/s
  if ( trim(tracname(igas))=='radon' .or. tracname(igas)(1:2)=='Rn' ) then
    decay = .true.
  end if
  
  methloss = tracname(igas)(1:7)=='methane'  ! check for methane tracers to set flag to do loss
  mcfloss  = tracname(igas)(1:3)=='mcf'      ! check for mcf tracers to set flag to do loss

  ! deposition and decay terms
  call gasvmix(updtr,gasfact,igas,decay,trsrc,methloss,mcfloss,cdtq,dz(:,1))
  
  call trimt(at,ct,updtr)
  tr(1:ifull,:,igas) = updtr  
  
end do

return
end subroutine tracervmix

! ***************************************************************************
!     this routine put the correct tracer surface flux into trsrc
subroutine trgassflux(igas,trsrc)

use cable_ccam, only : cbmemiss
use carbpools_m 
use cable_def_types_mod, only : ncs, ncp 
use nsibd_m
use tracermodule, only : co2em,tracdaytime,traclevel
use tracers_m, only : tracname,tractype

implicit none

include 'newmpar.h'
include 'dates.h' 

integer igas, ierr, k
real, dimension(ifull,kl), intent(out) :: trsrc
integer nchar, mveg

!     initialise (to allow for ocean gridpoints for cbm fluxes)      
!     and non surface layers
trsrc = 0.

select case(trim(tractype(igas)))
    
  case('online')
    if (trim(tracname(igas)(1:3)).eq.'cbm') then
      select case (trim(tracname(igas)))
        case('cbmnep'); trsrc(:,1) = fnee
        case('cbmpn');  trsrc(:,1) = fpn
        case('cbmrp');  trsrc(:,1) = frp
        case('cbmrs');  trsrc(:,1) = frs
        case default;   stop 'unknown online tracer name'
      end select
    else
      nchar = len_trim(tracname(igas))
      read(tracname(igas)(nchar-1:nchar),'(i2)',iostat=ierr) mveg
      if (ierr/=0) then
        write(6,*) 'unknown online tracer name or veg type number'
        write(6,*) trim(tracname(igas)),ierr
        stop
      end if
      if (mveg<1.or.mveg>maxval(ivegt)) stop 'tracer selection: veg type out of range'
      select case (tracname(igas)(1:nchar-2))
        case('gpp');    call cbmemiss(trsrc(:,1),mveg,1)
        case('plresp'); call cbmemiss(trsrc(:,1),mveg,2)
        case('slresp'); call cbmemiss(trsrc(:,1),mveg,3)
        case default;   stop 'unknown online tracer name'
      end select
    endif
    
  case ('daypulseon')
    ! only add flux during day time
    if (tracdaytime(igas,1)<tracdaytime(igas,2) .and. tracdaytime(igas,1)<=timeg .and. tracdaytime(igas,2)>=timeg) then
      trsrc(:,1) = co2em(:,igas)
    elseif (tracdaytime(igas,1)>tracdaytime(igas,2) .and. (tracdaytime(igas,1)<=timeg .or. tracdaytime(igas,2)>=timeg)) then
      trsrc(:,1) = co2em(:,igas)
    else
      trsrc(:,1) = 0.
    endif
    
  case default
    ! emissions from file over levels
    do k=1,traclevel(igas)
      trsrc(:,k) = co2em(:,igas)/real(traclevel(igas))
    end do
    
end select

return
end subroutine trgassflux

! *****************************************************************
subroutine gasvmix(temptr,fluxfact,igas,decay,trsrc,methloss,mcfloss,vt,dz1)

use arrays_m
use cc_mpi
use sigs_m 
use tracermodule, only : oh,strloss,mcfdep,jmcf,trdep
use tracers_m  
use xyzinfo_m   

implicit none

include 'newmpar.h'
include 'const_phys.h'
include 'parm.h' 

integer, intent(in) :: igas
integer k, iq
real, dimension(ifull,kl), intent(out) :: temptr
real, dimension(ifull,kl) :: loss
real, dimension(ifull,kl), intent(in) :: trsrc
real, dimension(ifull), intent(in) :: vt, dz1
real, dimension(ifull) :: dep
real, intent(in) :: fluxfact
real drate
real, dimension(1) :: totloss_l, totloss
logical, intent(in) :: decay, methloss, mcfloss

real, parameter :: koh    = 2.45e-12
real, parameter :: kohmcf = 1.64e-12

! decay rate for radon (using units of source, Bq/m2/s, to
! indicate that radon and need decay
if (decay) then
  drate = exp(-dt*2.11e-6)
else
  drate = 1.
endif

! rml 16/2/10 methane loss by OH and in stratosphere
if (methloss) then
  loss = tr(1:ilt*jlt,:,igas)*dt*(koh*exp(-1775./t(1:ilt*jlt,:))*oh(:,:) + strloss(:,:))

!       calculate total loss
  totloss_l(1) = 0.
  do k=1,kl
    do iq=1,ilt*jlt
      totloss_l(1) = totloss_l(1) + loss(iq,k)*dsig(k)*ps(iq)*wts(iq)
    enddo
  enddo
  call ccmpi_allreduce(totloss_l(1:1),totloss(1:1),"sum",comm_world)
!       convert to TgCH4 and write out
  if (myid == 0) then
    totloss(1) = -totloss(1)*4.*pi*eradsq*fCH4_MolM/(grav*fAIR_MolM*1.e18)
    write(6,*) 'Total loss',ktau,totloss(1)
!         accumulate loss over month
    acloss_g(igas) = acloss_g(igas) + totloss(1)
  endif
  dep = 0.
elseif (mcfloss) then
  loss = tr(1:ifull,:,igas)*dt*(kohmcf*exp(-1520./t(1:ifull,:))*oh(:,:) + jmcf(:,:))
  ! deposition
  dep  = exp(-mcfdep*dt/dz1)
elseif (trdep(igas)>0.) then
  loss = 0.
  dep  = exp(-vt*dt/dz1)
else
  loss = 0.
  dep  = 1.
endif

! implicit version due to potentially high transfer velocity relative to dz1
temptr(:,1)   = tr(1:ifull,1,igas)*drate*dep - fluxfact*grav*dt*trsrc(:,1)/(dsig(1)*ps(1:ifull)) - loss(:,1)
do k=2,kl
  temptr(:,k) = tr(1:ifull,k,igas)*drate - fluxfact*grav*dt*trsrc(:,k)/(dsig(k)*ps(1:ifull)) - loss(:,k)
end do

return
end subroutine gasvmix

! *********************************************************************
!     This is a copy of trim.f but trying to do all tracers at once.  
!     u initially now contains rhs; leaves with answer u (jlm)
!     n.b. we now always assume b = 1-a-c

subroutine trimt(a,c,rhs)

implicit none

include 'newmpar.h'
!     N.B.  e, g, temp are just work arrays (not passed through at all)     

integer k
real, dimension(ifull,kl), intent(inout) :: rhs
real, dimension(ifull,kl) :: g
real, dimension(ifull,kl), intent(in) :: a, c
real, dimension(ifull,kl) :: e, temp
real, dimension(ifull) :: b

!     this routine solves the system
!       a(k)*u(k-1)+b(k)*u(k)+c(k)*u(k+1)=rhs(k)    for k=2,kl-1
!       with  b(k)*u(k)+c(k)*u(k+1)=rhs(k)          for k=1
!       and   a(k)*u(k-1)+b(k)*u(k)=rhs(k)          for k=kl

!     the Thomas algorithm is used
!     save - only needed if common/work removed

b(:)=1.-a(:,1)-c(:,1)
e(:,1)=c(:,1)/b(:)
do k=2,kl-1
  b(:)=1.-a(:,k)-c(:,k)
  temp(:,k)= 1./(b(:)-a(:,k)*e(:,k-1))
  e(:,k)=c(:,k)*temp(:,k)
enddo

!     use precomputed values of e array when available
b(:)=1.-a(:,1)-c(:,1)
g(:,1)=rhs(:,1)/b(:)
do k=2,kl-1
  g(:,k)=(rhs(:,k)-a(:,k)*g(:,k-1))*temp(:,k)
end do

!     do back substitution to give answer now
b(:)=1.-a(:,kl)-c(:,kl)
rhs(:,kl)=(rhs(:,kl)-a(:,kl)*g(:,kl-1))/(b(:)-a(:,kl)*e(:,kl-1))
do k=kl-1,1,-1
  rhs(:,k)=g(:,k)-e(:,k)*rhs(:,k+1)
end do
      
return
end subroutine trimt

! Calculate settling
! Based on dust settling in aerosolldr.f90
subroutine trsettling(rhoa,tmp,delz,prf)

use tracermodule, only : trden, trreff
use tracers_m

implicit none

include 'newmpar.h'
include 'const_phys.h'
include 'parm.h'

real, dimension(ifull,kl), intent(in) :: rhoa   !air density (kg/m3)
real, dimension(:,:), intent(in) :: tmp         !temperature (K)
real, dimension(ifull,kl), intent(in) :: delz   !Layer thickness (m)
real, dimension(ifull,kl), intent(in) :: prf    !Pressure (hPa)
real, dimension(ifull) :: c_stokes, corr, c_cun
real, dimension(ifull) :: newtr, b, dfall
real, dimension(ifull,kl) :: vd_cor
integer nt,l

! Start code : ----------------------------------------------------------

do nt = 1, ngas
    
  if ( trden(nt)>0. .and. trreff(nt)>0. ) then
    
    ! Settling velocity (m/s)  (Stokes Law)
    ! TRDEN       soil class density             (kg/m3)
    ! TRREFF      effective radius               (m)
    ! grav        gravity                        (m/s2)

    ! Solve at the model top
    ! Dynamic viscosity
    C_Stokes = 1.458E-6 * TMP(1:ifull,kl)**1.5/(TMP(1:ifull,kl)+110.4) 
    ! Cuningham correction
    Corr = 6.6E-8*prf(:,kl)/1013.*TMP(1:ifull,kl)/293.15
    C_Cun = 1. + 1.249*corr/trreff(nt)
    ! Settling velocity
    Vd_cor(:,kl) =2./9.*grav*trden(nt)*trreff(nt)**2/C_Stokes*C_Cun
    ! Solve each vertical layer successively (layer l)
    do l = kl-1,1,-1
      ! Dynamic viscosity
      C_Stokes = 1.458E-6*TMP(1:ifull,l)**1.5/(TMP(1:ifull,l)+110.4) 
      ! Cuningham correction
      Corr = 6.6E-8*prf(:,l)/1013.*TMP(1:ifull,l)/293.15
      C_Cun = 1. + 1.249*corr/trreff(nt)
      ! Settling velocity
      Vd_cor(:,l) = 2./9.*grav*trden(nt)*trreff(nt)*trreff(nt)/C_Stokes*C_Cun
    end do
  
    ! Update mixing ratio
    b = dt*VD_cor(:,kl)/DELZ(:,kl)
    newtr = tr(1:ifull,kl,nt)*exp(-b)
    newtr = max( newtr, 0. )
    dfall = max( tr(1:ifull,kl,nt) - newtr, 0. )
    tr(1:ifull,kl,nt) = newtr
    ! Solve each vertical layer successively (layer l)
    do l = kl-1,1,-1
      ! Update mixing ratio
      b = dt*Vd_cor(:,l)/DELZ(:,l)
      dfall = dfall * delz(:,l+1)*rhoa(:,l+1)/(delz(:,l)*rhoa(:,l))
      ! Fout  = 1.-exp(-b)
      ! Fthru = 1.-Fout/b
      newtr = tr(1:ifull,l,nt)*exp(-b) + dfall*(1.-exp(-b))/b
      newtr = max( newtr, 0. )
      dfall = max( tr(1:ifull,l,nt) + dfall - newtr, 0. )
      tr(1:ifull,l,nt) = newtr
    end do
  end if
end do

return
end subroutine trsettling

! ********************************************************************
end module trvmix
