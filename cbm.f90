! cbm.f90
!
! Main source file for CABLE, CSIRO land surface model
!
! Science development by Ying-Ping Wang, Eva Kowalczyk, Mike Raupach, 
! Ray Leuning et al at CSIRO Marine and Atmospheric Research.
!
! Fortran-95 coding by Harvey Davies and Gab Abramowitz,
! bugs to gabsun@gmail.com.
!
! This file contains modules:
! cbm_module, air_module, roughness_module, radiation_module, 
! and canopy_module.

!===================================================================
 
!=========================================================================
MODULE air_module
  USE physical_constants
  USE define_types
  IMPLICIT NONE
  PRIVATE
  PUBLIC define_air
CONTAINS
  !-----------------------------------------------------------------------
  SUBROUTINE define_air(met,air)
    TYPE (air_type), INTENT(OUT) :: air
    TYPE (met_type), INTENT(IN)	 :: met
    REAL(r_1), DIMENSION(mp)	 :: es	! sat vapour pressure (mb)
    es	 = tetena * EXP(tetenb * (met%tvair-tfrz)/(tetenc + (met%tvair-tfrz)))
    air%cmolar = met%pmb * 100.0 / (rgas * (met%tvair))
    air%rho = min(1.3,rmair * air%cmolar)
    air%volm = rgas * (met%tvair) / (100.0 * met%pmb)
    air%rlam = (2501.0 - 2.38 * (met%tvair- tfrz)) * 1000.0
    air%rlam=2.5104e6
    air%qsat = (rmh2o / rmair) * es / met%pmb
    air%epsi = (air%rlam / capp) * (rmh2o / rmair) * es * tetenb * tetenc / &
         (tetenc + (met%tvair - tfrz)) ** 2 / met%pmb
    air%visc = 1e-5 * MAX(1.0, 1.35 + 0.0092 * (met%tvair - tfrz))
    air%psyc = met%pmb * 100.0 * capp * rmair / air%rlam / rmh2o
    air%dsatdk = (610.078 * 17.27 * 237.3) / ((met%tvair-tfrz)+237.2)** 2 * &
         EXP(17.27 * (met%tvair-tfrz) / ((met%tvair-tfrz) + 237.3))
  END SUBROUTINE define_air
END MODULE air_module
!=========================================================================
MODULE roughness_module
  USE physical_constants
  USE define_types
  IMPLICIT NONE
  PRIVATE
  PUBLIC ruff_resist
CONTAINS
  !-------------------------------------------------------------------
  SUBROUTINE ruff_resist(veg, rough, ssoil)
    ! m.r. raupach, 24-oct-92
    ! see: Raupach, 1992, BLM 60 375-395
    !      MRR notes "Simplified wind model for canopy", 23-oct-92
    !      MRR draft paper "Simplified expressions...", dec-92
    ! modified to include resistance calculations by Ray leuning 19 Jun 1998   
    TYPE (veg_parameter_type), INTENT(INOUT)	   :: veg
    TYPE (soil_snow_type), INTENT(IN)	   :: ssoil
    TYPE (roughness_type), INTENT(INOUT) :: rough
    REAL(r_1), DIMENSION(mp)	   :: term2, term3, term5
    REAL(r_1), DIMENSION(mp)	   :: hruff ! canopy height (above snow level)
    REAL(r_1), DIMENSION(mp)	   :: xx ! temporary
    REAL(r_1), DIMENSION(mp)	   :: dh ! d/h where d is zero-plane displacement
    ! Set canopy height above snow level:
    hruff= MAX(0.01,veg%hc-1.2*ssoil%snowd/max(ssoil%ssdnn,100.)) 
    rough%zref = max(hruff+2.,rough%za)	 ! needs more elaborate formula
    ! LAI decreases due to snow and vegetation fraction:
    veg%vlaiw = veg%vlai * hruff/MAX(0.01,veg%hc)
    rough%z0soilsn = max(min(-7.5e-6*(0.01*min(ssoil%snowd,20.))+z0soil,z0soil),0.2e-7)
    WHERE (veg%vlaiw.LT.0.001 .OR. hruff.LT. rough%z0soilsn)
       rough%z0m	 = rough%z0soilsn	       ! BARE SOIL SURFACE
       hruff	   = 0.0
       rough%rt0us  = 0.0
       rough%disp	 = 0.0
       rough%zruffs = 0.0
       rough%rt1usa = 0.0
       rough%rt1usb = 0.0
       !	    rough%usuh	 = usuhm
       rough%usuh        = MIN(SQRT(cs+cr*(veg%vlaiw*0.5)), usuhm)
       xx          = SQRT(ccd*MAX((veg%vlaiw*0.5),0.0005))
       dh          = 1.0 - (1.0 - EXP(-xx))/xx
       rough%coexp       = rough%usuh / (vonk*ccw*(1.0 - dh))
    ELSEWHERE ! VEGETATED SURFACE
       rough%usuh	 = MIN(SQRT(cs+cr*(veg%vlaiw*0.5)), usuhm)
       xx	   = SQRT(ccd*MAX((veg%vlaiw*0.5),0.0005))
       dh	   = 1.0 - (1.0 - EXP(-xx))/xx
       rough%disp = dh*hruff
       rough%z0m =((1.0 - dh)*EXP(LOG(ccw)-1. + 1./ccw - vonk/rough%usuh))*hruff
       !	find coexp: see notes "simplified wind model ..." eq 34a
       rough%coexp  = rough%usuh / (vonk*ccw*(1.0 - dh))
       !	rt0 = turbulent resistance from soil (z0 = 0) to canopy
       !	(z1 = zero-plane displacement), normalized as rt0us=rt0*us
       !	nb: term4 added 13-sep-95 to make TL proportional to z near ground.
       !	nb: term5 added 03-oct-96 to account for sparse canopies. Constant
       !	length scale ctl*hruf replaced by ctl*(3/2)*disp, taking effect
       !	when disp<(2/3)*hruf, or total LAI < 1.11. Otherwise, term5=1.
       term2  = EXP(2*csw*veg%vlaiw*(1-rough%disp/hruff))
       term3  = a33**2*ctl*2*csw*veg%vlaiw
       term5  = MAX((2./3.)*hruff/rough%disp, 1.0)
       rough%rt0us  = term5*(zdlin*LOG(zdlin*rough%disp/rough%z0soilsn) &
            + (1-zdlin))*(EXP(2*csw*veg%vlaiw) - term2)/term3
       !	rt1 = turbulent resistance from canopy (z1 = disp) to
       !	reference level zref (from disp as origin). Normalisation:
       !	rt1us = us*rt1 = rt1usa + rt1usb + rt1usc
       !	with term a = resistance from disp to hruf
       !	term b = resistance from hruf to zruffs (or zref if zref<zruffs)
       !	term c = resistance from zruffs to zref (= 0 if zref<zruffs)
       !	where zruffs = SCALAR roughness sublayer depth (ground=origin)
       !	xzrufs = xdisp + xhruf*a33**2*ctl/vonk
       ! See CSIRO SCAM, Raupach et al 1997, eq. 3.49:
       rough%zruffs = rough%disp + hruff*a33**2*ctl/vonk/term5
       ! See CSIRO SCAM, Raupach et al 1997, eq. 3.51:
       rough%rt1usa = term5*(term2 - 1.0)/term3
       rough%rt1usb = term5*(MIN(rough%zref+rough%disp,rough%zruffs) - hruff)/ &
            (a33**2*ctl*hruff)
       rough%rt1usb = MAX(rough%rt1usb,0.0)       ! in case zrufs < hruff
    END WHERE
  END SUBROUTINE ruff_resist

END MODULE roughness_module
!=========================================================================

MODULE abort_module
  IMPLICIT NONE
CONTAINS
  SUBROUTINE abort(message)
    CHARACTER(LEN=*), INTENT(IN)	:: message
    WRITE(*, *) message
    STOP 1
  END SUBROUTINE abort
END MODULE abort_module
!================================================================================
MODULE radiation_module
  ! use Goudriaan's radiation scheme for calculate radiation absorbed by canopy 
  ! and soil, treat diffuse, direct separately for three wavebands (nrb),
  ! nrb=1, visible; =2 for nir and 3 for thermal
  ! input variables
  !  fsd: incoming shortwave (0.5 visible, 0.5 nir)
  !  fld: incoming longwave radiation
  !  veg%vlai: canopy LAI
  !  veg%xfang: leaf inclination angle distrbution parameter (<0 more vertical)
  !                                                          =0 spherical
  !                                                          >0 more horizontal)
  !  rad%latitude: site latitude in degree (- for SH and + for NH)
  !  soil%ref: soil reflectance
  !  taul: leaf transmittance
  !  rhol: leaf reflectance
  ! output varibales
  !  qcan: absorbed radiation by canopy
  !  qssabs: absorbed radiation (shortwave only) by soil
  !  scalex: scaling for sunlit/shaded leaves
  !  transd: diffuse transmittance of canopy
  !  rad%fvlai: LAI of sunlit/shaded leaves
  !  rad%albedo: surface (canopy+soil) albedo
  !  rad%gradis: isothermal radiative conductance
 
  USE math_constants
  USE other_constants
  USE define_types
  USE physical_constants
  USE abort_module
  IMPLICIT NONE
  ! This module contains the following subroutines:
  PRIVATE
  PUBLIC init_radiation, radiation, sinbet ! available outside this module
  PRIVATE spitter ! available only from within this module
CONTAINS
  !--------------------------------------------------------------------------
  SUBROUTINE init_radiation(rad,veg)
    TYPE (veg_parameter_type), INTENT(IN) :: veg
    TYPE (radiation_type), INTENT(INOUT) :: rad
    REAL(r_1), DIMENSION(nrb)   :: c1    ! sqrt(1. - taul - refl)
    REAL(r_1), DIMENSION(3)     :: cos3  ! cos(15 45 75 degrees)
    REAL(r_1), DIMENSION(nrb)   :: rhoch ! canopy reflect'n black horiz leaves(6.19)
    REAL(r_1), DIMENSION(mp,3)  :: xvlai2 ! 2D vlai
    REAL(r_1), DIMENSION(mp,3)  :: xk    ! ???
    REAL(r_1), DIMENSION(mp)    :: xphi1 ! leaf angle parmameter 1
    REAL(r_1), DIMENSION(mp)    :: xphi2 ! leaf angle parmameter 2
    cos3 = COS(pi180 * (/ 15.0, 45.0, 75.0 /))
    WHERE (veg%vlaiw > 1e-3)
       ! See Sellers 1985, eq.13:
       xphi1 = 0.5 - veg%xfang * (0.633 + 0.33 * veg%xfang)
       xphi2 = 0.877 * (1.0 - 2.0 * xphi1)
    END WHERE
    xvlai2 = SPREAD(veg%vlaiw, 2, 3)
    WHERE (xvlai2 > 1e-3)
       xk = SPREAD(xphi1, 2, 3) / SPREAD(cos3, 1, mp) + SPREAD(xphi2, 2, 3)
    ELSEWHERE ! i.e. bare soil
       xk = 0.0		 
    END WHERE
    WHERE (veg%vlaiw > 1e-3)
       rad%extkd = -LOG(SUM(SPREAD(gauss_w, 1, mp) * EXP(-xk * xvlai2), 2)) / veg%vlaiw
    ELSEWHERE ! i.e. bare soil
       rad%extkd = 0.7
    END WHERE
    rad%extkn = rad%extkd * SQRT(1.0 - taul(1) - refl(1))
    c1 = SQRT(1. - taul - refl)
    rhoch = (1.0 - c1) / (1.0 + c1)
    rad%rhocdf = SPREAD(2.0 * gauss_w * rhoch, 1, mp) * xk / (xk + SPREAD(rad%extkd, 2, 3))
  END SUBROUTINE init_radiation
  !-------------------------------------------------------------------------------
  SUBROUTINE radiation(bal, soil, ssoil, veg, air, met, rad)
    TYPE (soil_parameter_type),INTENT(IN)	        :: soil
    TYPE (soil_snow_type),INTENT(INOUT)	:: ssoil
    TYPE (veg_parameter_type),INTENT(IN)	        :: veg
    TYPE (air_type),INTENT(IN)	        :: air
    TYPE (met_type),INTENT(INOUT)	:: met
    TYPE (radiation_type),INTENT(INOUT)	:: rad
    TYPE (balances_type),INTENT(INOUT)  :: bal
    REAL(r_1), DIMENSION(nrb) :: c1	! sqrt(1. - taul - refl)
    REAL(r_1), DIMENSION(mp)  :: cexpkbm ! canopy beam transmittance
    REAL(r_1), DIMENSION(mp)  :: cexpkdm ! canopy diffuse transmittance
    REAL(r_1), DIMENSION(mp)  :: cf1	! (1.0 - transb * cexpkdm) / (extkb + extkdm(:,b))
    REAL(r_1), DIMENSION(mp)  :: cf3	! (1.0 - transb * cexpkbm) / (extkb + extkbm(:,b))
    REAL(r_1), DIMENSION(mp)  :: cf2n	! exp(-extkn * vlai) (nitrogen)
    REAL(r_1), DIMENSION(mp)  :: emair	! air emissivity
    REAL(r_1), DIMENSION(mp,nrb) :: extkbm	! modified k beam(6.20)(for leaf scattering)
    REAL(r_1), DIMENSION(mp,nrb) :: extkdm ! modified k diffuse(6.20)(for leaf scattering)
    REAL(r_1), DIMENSION(mp)  :: fbeam	! beam fraction
    REAL(r_1), DIMENSION(mp)  :: flpwb	! black-body long-wave radiation
    REAL(r_1), DIMENSION(mp)  :: flwv	! vegetation long-wave radiation (isothermal)
    LOGICAL, DIMENSION(mp)    :: mask	! select points for calculation
    INTEGER(i_d)	      :: b ! rad. band 1=visible, 2=near-infrared, 3=long-wave
    REAL(r_1), DIMENSION(mp,nrb) :: reffbm	! effective conopy beam reflectance
    REAL(r_1), DIMENSION(mp,nrb) :: reffdf	! effective conopy diffuse reflectance
    REAL(r_1), DIMENSION(nrb)    :: rhoch ! canopy reflection black horizontal leaves(6.19)
    REAL(r_1), DIMENSION(mp,nrb) :: rhocbm	! modified canopy beam reflectance (6.21)
    REAL(r_1), DIMENSION(mp)     :: transb	! fraction SW beam tranmitted through canopy
    REAL(r_1), DIMENSION(mp)     :: xphi1	! leaf angle parmameter 1
    REAL(r_1), DIMENSION(mp)     :: xphi2	! leaf angle parmameter 2
    INTEGER(i_d) :: ijd,k
        !
        ijd = 3688
        ijd = 2468
    ! coszen is set during met data read in.
    reffbm = 0.0 ! initialise
    ! Define beam fraction, fbeam:
    fbeam = spitter(met%doy, met%coszen, met%fsd)
    where (met%coszen <1.0e-2)
       fbeam = 0.0
    endwhere
    ! Define vegetation mask:
    mask = veg%vlaiw > 1e-3 .AND. met%fsd > 1.0e-10
!    mask = veg%vlaiw > 1e-3 
    cf2n = EXP(-rad%extkn * veg%vlaiw)
    ! See Sellers 1985, eq.13:
    xphi1 = 0.5 - veg%xfang * (0.633 + 0.33 * veg%xfang)
    xphi2 = 0.877 - (0.877 * 2.0) * xphi1
    WHERE (veg%vlaiw > 1e-3)    ! In gridcells where vegetation exists....
       ! SW beam extinction coefficient ("black" leaves, extinction neglects
       ! leaf SW transmittance and reflectance):
       rad%extkb = xphi1 / met%coszen + xphi2
       ! Diffuse SW transmission fraction ("black" leaves, extinction neglects
       ! leaf SW transmittance and reflectance);
       ! from Monsi & Saeki 1953, quoted in eq. 18 of Sellers 1985:
       rad%transd = EXP(-rad%extkd * veg%vlaiw)
    ELSEWHERE	! i.e. bare soil
       rad%extkb = 0.5
       rad%transd = 1.0
    END WHERE
    where(fbeam < 1.0e-3)
       rad%extkb=1.0e5
    endwhere

    transb = EXP(-rad%extkb * veg%vlaiw)
    ! Define longwave from vegetation (flwv - isothermal), then soil (flws):
    flpwb = sboltz * (met%tvrad) ** 4
    flwv = emleaf * flpwb
    ssoil%tss=(1-ssoil%isflag)*ssoil%tgg(:,1) + ssoil%isflag*ssoil%tggsn(:,1)
    rad%flws = sboltz*emsoil* ssoil%tss **4
    ! Define gradis, qcan for long wave:
    emair = met%fld / flpwb
    rad%gradis = 0.0 ! initialise
    rad%qcan = 0.0   ! initialise
    WHERE (veg%vlaiw > 1.e-3)
       ! Define radiative conductance (Leuning et al, 1995), eq. D7:
       rad%gradis(:,1) = (4.0 * emleaf / (capp * air%rho)) * flpwb / &
            (met%tvrad) * rad%extkd * &
            ((1.0 - transb * rad%transd) / (rad%extkb + rad%extkd) + &
            (rad%transd - transb) / (rad%extkb - rad%extkd))
       rad%gradis(:,2) = (8.0 * emleaf / (capp * air%rho)) * flpwb / (met%tvrad) * &
            rad%extkd * (1.0 - rad%transd) / rad%extkd - rad%gradis(:,1)
       ! Longwave radiation absorbed by sunlit canopy fraction:
       rad%qcan(:,1,3) = (rad%flws-flwv) *rad%extkd * (rad%transd - transb) / &
            (rad%extkb - rad%extkd) &
            + (emair - emleaf) * rad%extkd * flpwb * (1.0 - rad%transd * transb) / &
            ( rad%extkb + rad%extkd) 
       ! Longwave radiation absorbed by shaded canopy fraction:
       rad%qcan(:,2,3) = (1.0 - rad%transd) * &
            (rad%flws + flpwb * (emair - 2.0 * emleaf)) - rad%qcan(:,1,3) 
    END WHERE
    ! Convert radiative conductance from m/s to mol/m2/s:
    rad%gradis=SPREAD(air%cmolar, 2, mf)*rad%gradis
    rad%gradis = MAX(1.e-3,rad%gradis)
    c1 = SQRT(1. - taul - refl)
    rhoch = (1.0 - c1) / (1.0 + c1)
    ! updating extinction coefficients and fractional transmittance for 
    ! leaf transmittance and reflection (ie. NOT black leaves)
    DO b = 1, 2				! 1 = vis, 2 = nir
       extkdm(:,b) = rad%extkd * c1(b)
       ! Define canopy diffuse transmittance (fraction):
       cexpkdm = EXP(-extkdm(:,b) * veg%vlaiw)
       ! Calculate effective diffuse reflectance (fraction):
       reffdf(:,b) = rad%rhocdf(:,b) + &
            (ssoil%albsoilsn(:,b) - rad%rhocdf(:,b)) * cexpkdm**2
       WHERE (mask)
          extkbm(:,b) = rad%extkb * c1(b)
          ! Canopy reflection (6.21) beam:
          rhocbm(:,b) = 2.*rad%extkb/(rad%extkb+rad%extkd)*rhoch(b)
          ! Canopy beam transmittance (fraction):
          cexpkbm = EXP(-extkbm(:,b)*veg%vlaiw)
          ! Calculate effective beam reflectance (fraction):
          reffbm(:,b) = rhocbm(:,b) + (ssoil%albsoilsn(:,b) - rhocbm(:,b))*cexpkbm*cexpkbm
          cf1 = (1.0 - transb * cexpkdm) / (rad%extkb + extkdm(:,b))
          cf3 = (1.0 - transb * cexpkbm) / (rad%extkb + extkbm(:,b))
          ! Define qcan for short wave (par, nir) for sunlit leaf:
          rad%qcan(:,1,b) = 0.5 * met%fsd * ( &		! scale to real sunlit flux
               (1.0-fbeam)*(1.0-reffdf(:,b))*extkdm(:,b)*cf1 &
               + fbeam*(1.0-reffbm(:,b))*extkbm(:,b)*cf3 &
               + fbeam*(1.0-taul(b)-refl(b))*rad%extkb &
               * ((1-transb)/rad%extkb - (1-transb**2)/(rad%extkb+rad%extkb)))
          ! Define qcan for short wave (par, nir) for shaded leaf:
          rad%qcan(:,2,b) = 0.5 * met%fsd * ( &		! scale to real shaded flux
               (1.0-fbeam)*(1.0-reffdf(:,b))*extkdm(:,b)* &
               ((1.0 - cexpkdm) / extkdm(:,b) - cf1) &
               + fbeam*(1.-reffbm(:,b))*extkbm(:,b) &
               * ((1.0 - cexpkbm) / extkbm(:,b) - cf3) &
               - fbeam*(1.0-taul(b)-refl(b))*rad%extkb &
               * ((1-transb)/rad%extkb - (1-transb**2)/(rad%extkb+rad%extkb)))
       END WHERE
       ! Define albedo:
       rad%albedo(:,b) = (1.0-fbeam)*reffdf(:,b)+fbeam*reffbm(:,b)
    END DO    
    ! Total energy absorbed by canopy:
    WHERE (mask)
       ! Calculate shortwave radiation absorbed by soil:
       ! (av. of transmitted NIR and PAR through canopy)*SWdown
       rad%qssabs = 0.5 * met%fsd * ( &
            fbeam*(1.-reffbm(:,1))*EXP(-extkbm(:,1)*veg%vlaiw) &
            +(1.-fbeam)*(1.-reffdf(:,1))*EXP(-extkdm(:,1)*veg%vlaiw) + &
            fbeam*(1.-reffbm(:,2))*cexpkbm +(1.-fbeam)*(1.-reffdf(:,2))*cexpkdm)
       ! Scaling from single leaf to canopy, see Wang & Leuning 1998 appendix C:
       rad%scalex(:,1) = (1.0 - transb * cf2n) / (rad%extkb + rad%extkn)
       rad%fvlai(:,1) = (1.0 - transb) / rad%extkb
       rad%fvlai(:,2) = veg%vlaiw - rad%fvlai(:,1)
    ELSEWHERE
       rad%qssabs = (1.0 - (0.5 * (ssoil%albsoilsn(:,1) + ssoil%albsoilsn(:,2)))) * met%fsd
       rad%scalex(:,1) = 0.0
       rad%fvlai(:,1) = 0.0
       rad%fvlai(:,2) = veg%vlaiw
    END WHERE
    rad%scalex(:,2) = (1.0 - cf2n) / rad%extkn - rad%scalex(:,1)
    rad%rniso = sum(rad%qcan, 3)

  END SUBROUTINE radiation
  !-----------------------------------------------------------------
  ELEMENTAL FUNCTION sinbet(doy,xslat,hod) RESULT(z)
    ! calculate sin(bet), bet = elevation angle of sun
    ! calculations according to goudriaan & van laar 1994 p30
    REAL(r_1), INTENT(IN)	:: doy		! day of year
    REAL(r_1), INTENT(IN)	:: xslat	! latitude (degrees north)
    REAL(r_1), INTENT(IN)	:: hod		! hour of day
    REAL(r_1)			:: sindec	! sine of maximum declination
    REAL(r_1)			:: z		! result
    sindec = -SIN(23.45 * pi180) * COS(two_pi * (doy + 10.0) / 365.0)
    z = MAX( &
         SIN(pi180 * xslat) * sindec + COS(pi180 * xslat) * SQRT(1. - sindec * sindec) &
         * COS(pi * (hod - 12.) / 12.), 1e-8)
  END FUNCTION sinbet
  !-------------------------------------------------------------------
  FUNCTION spitter(doy, coszen, fsd) RESULT(fbeam)
    ! Calculate beam fraction
    ! See spitters et al. 1986, agric. for meteorol., 38:217-229
    REAL(r_1), DIMENSION(mp), INTENT(IN) :: doy	! day of year
    REAL(r_1), DIMENSION(mp), INTENT(IN) :: coszen ! cos(zenith angle of sun)
    REAL(r_1), DIMENSION(mp), INTENT(IN) :: fsd	! short wave down (positive) w/m^2
    REAL(r_1), DIMENSION(mp) :: fbeam	! beam fraction (result)
    REAL(r_1), PARAMETER	 :: solcon = 1370.0
    REAL(r_1), DIMENSION(mp) :: tmpr
    REAL(r_1), DIMENSION(mp) :: tmpk
    REAL(r_1), DIMENSION(mp) :: tmprat
    fbeam = 0.0
    tmpr = 0.847 + coszen * (1.04 * coszen - 1.61)
    tmpk = (1.47 - tmpr) / 1.66
!    WHERE (coszen > 1.0e-10  .AND.	fsd > 1.0e-10)
    WHERE (coszen > 1.0e-10  .AND.	fsd > 10.)
       tmprat = fsd / (solcon * (1.0 + 0.033 * COS(two_pi * (doy-10.0) / 365.0)) * coszen)
    ELSEWHERE
       tmprat = 0.0
    END WHERE
    WHERE (tmprat > 0.22) fbeam = 6.4 * (tmprat - 0.22) ** 2
    WHERE (tmprat > 0.35) fbeam = MIN(1.66 * tmprat - 0.4728, 1.0)
    WHERE (tmprat > tmpk) fbeam = MAX(1.0 - tmpr, 0.0)
  END FUNCTION spitter
END MODULE radiation_module
!=========================================================================
MODULE canopy_module
  USE photosynthetic_constants
  USE radiation_module
  USE roughness_module
  USE air_module
  USE define_types
  USE physical_constants
  IMPLICIT NONE
  PRIVATE
  PUBLIC define_canopy
CONTAINS
  
  !--------------------------------------------------------------------------
  SUBROUTINE define_canopy(bal,rad,rough,air,met,dels,ssoil,soil,veg,bgc,canopy)
    TYPE (balances_type),INTENT(INOUT)  :: bal
    TYPE (radiation_type), INTENT(INOUT):: rad
    TYPE (roughness_type), INTENT(INOUT):: rough
    TYPE (air_type), INTENT(INOUT)	:: air
    TYPE (met_type), INTENT(INOUT)	:: met
    REAL(r_1), INTENT(IN)		:: dels ! integration time setp (s)
    TYPE (soil_snow_type), INTENT(INOUT):: ssoil
    TYPE (bgc_pool_type),INTENT(IN)	:: bgc
    TYPE (soil_parameter_type), INTENT(INOUT)	:: soil
    TYPE (veg_parameter_type), INTENT(INOUT)	:: veg
    TYPE (canopy_type), INTENT(INOUT)   :: canopy
    REAL(r_1), DIMENSION(mp,mf)	        :: abs_deltlf ! ABS(deltlf)
    REAL(r_1), DIMENSION(mp,mf,3)	:: ancj ! soln to quad eqn
    REAL(r_1), DIMENSION(mp,mf)		:: anx ! net photos. prev iteration
    REAL(r_1), DIMENSION(mp,mf)		:: an_y ! net photosynthesis soln
    REAL(r_1), DIMENSION(mp)		:: avgtrs !root weighted mean soil temperature
    REAL(r_1), DIMENSION(mp)		:: avgwrs !root weighted mean soil moisture
    REAL(r_1), DIMENSION(mp,mf)		:: ca2	 ! 2D ca
    REAL(r_1), DIMENSION(mp)		:: cansat ! max canopy intercept. (mm)
    REAL(r_2), DIMENSION(mp,mf,3)	:: ci ! intercellular CO2 conc.
    REAL(r_1), PARAMETER		:: co2cp3=0.0 ! CO2 compensation pt C3
    REAL(r_2), DIMENSION(mp,mf,3)	:: coef0 ! CO2 comp. pt coeff 1
    REAL(r_2), DIMENSION(mp,mf,3)	:: coef1 ! " 2
    REAL(r_2), DIMENSION(mp,mf,3)	:: coef2 ! " 3
    REAL(r_1), DIMENSION(mp,mf)		:: conkct ! Michaelis Menton const.
    REAL(r_1), DIMENSION(mp,mf)		:: conkot ! Michaelis Menton const.
    REAL(r_1), DIMENSION(mp,mf)		:: csx ! leaf surface CO2 concentration
    REAL(r_2), DIMENSION(mp,mf,3)	:: cx
    REAL(r_1), DIMENSION(mp,mf)		:: da2 ! 2D da
    REAL(r_1), DIMENSION(mp,mf)		:: dva2 ! 2D da
    REAL(r_2), DIMENSION(mp,mf,3)	:: delcx ! discriminant
    REAL(r_1), DIMENSION(mp,mf)		:: deltlf ! deltlfy of prev iter.
    REAL(r_1), DIMENSION(mp,mf)		:: deltlfy ! del temp successive iteration
    REAL(r_1), DIMENSION(mp)		:: dq ! sat spec hum diff.
    REAL(r_1), DIMENSION(mp,mf)		:: dsatdk2	! 2D dsatdk
    REAL(r_1), DIMENSION(mp,mf)		:: dsx ! leaf surface vpd
    REAL(r_2), DIMENSION(mp,mf)		:: ecx ! lat. hflux big leaf
    REAL(r_1), DIMENSION(mp,mf)		:: ejmax2 ! jmax of big leaf
    REAL(r_1), DIMENSION(mp,mf)		:: ejmxt3 ! jmax big leaf C3 plants
    REAL(r_2), DIMENSION(mp,mf)		:: ecy ! lat heat fl dry big leaf
    REAL(r_1), DIMENSION(mp,mf)		:: frac42	! 2D frac4
    REAL(r_1), DIMENSION(mp)		:: fwsoil ! soil water modifier of stom. cond.
    REAL(r_1), DIMENSION(mp)		:: gaw ! aerodynamic conduct. for water
    REAL(r_1), DIMENSION(mp,mf)		:: gaw2	! 2D gaw
    REAL(r_1), DIMENSION(mp,mf)		:: gbhf ! freeConvectionBndLayerConductance mol/m2/s
    REAL(r_1), DIMENSION(mp,mf)		:: gbhu ! forcedConvectionBoundaryLayerConductance
    REAL(r_1), DIMENSION(mp)		:: gbvtop ! bnd layer cond. top leaf
    REAL(r_1), DIMENSION(mp,mf)		:: gras ! Grashof coeff
    REAL(r_1), DIMENSION(mp,mf)		:: gswmin ! min stomatal conductance
    REAL(r_1), DIMENSION(mp,mf)		:: gswx ! stom cond for water
    REAL(r_1), DIMENSION(mp,mf)		:: gw  ! cond for water for a dry canopy
    REAL(r_1), DIMENSION(mp,mf)		:: gh  ! cond for heat for a dry canopy
    REAL(r_1), DIMENSION(mp,mf)		:: ghr ! dry canopy cond for heat & thermal radiat'n
    REAL(r_1), DIMENSION(mp)		:: gwwet  ! cond for water for a wet canopy
    REAL(r_1), DIMENSION(mp)		:: ghwet  ! cond for heat for a wet canopy
    REAL(r_1), DIMENSION(mp)		:: ghrwet ! wet canopy cond: heat & thermal radiat'n
    REAL(r_2), DIMENSION(mp,mf)		:: hcx ! sens heat fl big leaf prev iteration
    REAL(r_2), DIMENSION(mp,mf)		:: hcy ! veg. sens heat
    INTEGER(i_d)			:: iter ! iteration #
    INTEGER(i_d)			:: iterplus !
    INTEGER(i_d)			:: k		! interation count
    INTEGER(i_d)			:: kk		! interation count
    REAL(r_1), DIMENSION(mp,mf)		:: psycst ! modified pych. constant
    REAL(r_1), DIMENSION(mp,mf)		:: rdx ! daytime leaf resp rate, prev iteration
    REAL(r_1), DIMENSION(mp,mf)		:: rdy ! daytime leaf resp rate
    REAL(r_2), DIMENSION(mp,mf)		:: rnx ! net rad prev timestep
    REAL(r_2), DIMENSION(mp,mf)		:: rny ! net rad
    REAL(r_1), DIMENSION(mp)		:: rt0 ! turbulent resistance
    REAL(r_1), DIMENSION(mp)		:: ortsoil ! turbulent resistance
    REAL(r_1), DIMENSION(mp)		:: rt1usc !
    REAL(r_1), DIMENSION(mp)		:: rwater ! soil water availability
    REAL(r_1), DIMENSION(mp,mf)		:: tair2 ! 2D tair
    REAL(r_1), DIMENSION(mp,mf)		:: tvair2 ! 2D tair
    REAL(r_1), DIMENSION(mp,mf)		:: tdiff ! leaf air temp diff.
    REAL(r_1), DIMENSION(mp,mf)		:: tlfx ! leaf temp prev. iteration
    REAL(r_1), DIMENSION(mp,mf)		:: tlfxx
    REAL(r_1), DIMENSION(mp,mf)		:: tlfy ! leaf temp
    REAL(r_1), DIMENSION(mp,mf)		:: vcmax2 ! vcmax big leaf
    REAL(r_1), DIMENSION(mp,mf)		:: vcmxt3 ! vcmax big leaf C3
    REAL(r_1), DIMENSION(mp,mf)		:: vcmxt4 ! vcmax big leaf C4
    REAL(r_2), DIMENSION(mp,mf,2)	:: vx3 ! carboxylation C3 plants
    REAL(r_2), DIMENSION(mp,mf,2)	:: vx4 ! carboxylation C4 plants
    REAL(r_1), DIMENSION(mp)		:: wetfac ! ????
    REAL(r_1), DIMENSION(mp,mf)		:: xdleaf2	! 2D dleaf
    REAL(r_1), DIMENSION(mp,mf)		:: xleuning ! leuning stomatal coeff
    REAL(r_1), DIMENSION(mp,niter)	:: zetar ! stability correction
    REAL(r_1), PARAMETER		:: jtomol = 4.6e-6
    REAL(r_1), PARAMETER		:: EHaVc  = 73637.0  !J/mol (Leuning 2002)
    REAL(r_1), PARAMETER		:: EHdVc  = 149252.0 !J/mol (Leuning 2002)
    REAL(r_1), PARAMETER		:: EntropVc = 486.0  !J/mol/K (Leuning 2002)
    REAL(r_1), PARAMETER		:: xVccoef = 1.17461 !derived parameter
    !	xvccoef=1.0+exp((Entropjx*TrefK-EHdjx)/(Rconst*TrefK))
    REAL(r_1), PARAMETER		:: EHaJx  = 50300.0  !J/mol (Leuning 2002)
    REAL(r_1), PARAMETER		:: EHdJx  = 152044.0	!J/mol (Leuning 2002)
    REAL(r_1), PARAMETER		:: EntropJx = 495.0	!J/mol/K (Leuning 2002)
    REAL(r_1), PARAMETER		:: xjxcoef = 1.16715	!derived parameter
    REAL(r_1), PARAMETER		:: effc4 = 4000.0  !Vc=effc4*Ci*Vcmax (see
    ! Bonan,LSM version 1.0, p106)
    REAL(r_1), DIMENSION(mp)		:: oldcansto ! prev t step canopy storage
    REAL(r_1), DIMENSION(mp)		:: cc			   ! working variable
    REAL(r_1), DIMENSION(mp)		:: ccfevw		   ! working variable
    REAL(r_1), DIMENSION(mp)		:: denom
    REAL(r_1), DIMENSION(mp)		:: tstar
    REAL(r_1), DIMENSION(mp)		:: zscrn
    REAL(r_1), DIMENSION(mp)		:: qstar
    REAL(r_1), DIMENSION(mp)		:: rsts
    REAL(r_1), DIMENSION(mp)		:: qsurf
    REAL(r_1), DIMENSION(mp)		:: qtgnet
    REAL(r_1), DIMENSION(mp)		:: evapfb
    REAL(r_1), DIMENSION(mp,ms)		:: evapfbl
    REAL(r_1), DIMENSION(mp)		:: phenps
    REAL(r_1), DIMENSION(mp)		:: poolcoef1
    REAL(r_1), DIMENSION(mp)		:: poolcoef1w
    REAL(r_1), DIMENSION(mp)		:: poolcoef1r
    REAL(r_1), DIMENSION(mp)		:: rbw
    REAL(r_1), DIMENSION(mp)		:: rsw
    REAL(r_1), DIMENSION(mp)		:: dmah
    REAL(r_1), DIMENSION(mp)		:: dmbh
    REAL(r_1), DIMENSION(mp)		:: dmch
    REAL(r_1), DIMENSION(mp)		:: dmae
    REAL(r_1), DIMENSION(mp)		:: dmbe
    REAL(r_1), DIMENSION(mp)		:: dmce
    REAL(r_1), DIMENSION(mp,mf)		:: tss2
    REAL(r_1), DIMENSION(mp)		:: tss4 ! tss**4
    !	REAL(r_1), DIMENSION(mp)		:: sss
    !	REAL(r_1), DIMENSION(mp)		:: cc1
    !	REAL(r_1), DIMENSION(mp)		:: cc2
    REAL(r_1), DIMENSION(mp)		:: qstvair
    REAL(r_1), DIMENSION(mp)		:: qstss
    REAL(r_1), DIMENSION(mp)		:: xx
    REAL(r_1), DIMENSION(mp,mf)		:: temp ! vcmax big leaf C3
    INTEGER(i_d)                            :: ijd 
    !
    !	xjxcoef=1.0+exp((Entropjx*TrefK-EHdjx)/(Rconst*TrefK))
    ! 1-oct-2002 ypw: to keep the unit consistent for resistance or conductance
    ! s/m for r; mol/m2/s for g, and always use g where appropriate
    ! replace rh, rhr, rw  with ghdry/ghwet,ghrdry, ghrwet, gwdry, gwwet

    ! Set surface water vapour pressure deficit:
    ijd=2468
    met%da = (qsatf(met%tc,met%pmb) - met%qv ) * rmair/rmh2o * met%pmb * 100.

    rwater = MAX(1.0e-4, &
         SUM(soil%froot * MIN(1.0,ssoil%wb - SPREAD(soil%swilt, 2, ms)),2) &
         /(soil%sfc-soil%swilt))
    ! construct function to limit stom cond for soil water availability
    fwsoil = MAX(1.0e-4,MIN(1.0, veg%vbeta * rwater))
    ! BATS-type canopy saturation proportional to LAI:
    cansat = veg%canst1 * veg%vlaiw
    phenps = max (1.0e-4, MIN(1.,1. - ( (veg%tmaxvj - ssoil%tgg(:,4)+tfrz)/ &
         (veg%tmaxvj - veg%tminvj) )**2 ) )
    WHERE ( ssoil%tgg(:,4) < (veg%tminvj + tfrz) ) phenps = 0.0
    WHERE ( ssoil%tgg(:,4) > (veg%tmaxvj + tfrz) ) phenps = 1.0
    ! Set previous time step canopy water storage:
    oldcansto=canopy%cansto
    ! limited rainfall variable so canopy interception is limited,
    !  used to stabilise latent fluxes.
    cc =min(met%precip, 4./(1440./(dels/60.)))! to avoid canopy temp. oscillations
    ! Calculate canopy intercepted rainfall, equal to zero if temp < 0C:
    canopy%wcint = MERGE(MIN(MAX(cansat - canopy%cansto,0.0), cc), 0.0, &
         cc > 0.0  .AND. met%tk > tfrz)
    ! Define canopy throughfall (100% of precip if temp < 0C, see above):
    canopy%through = MIN(met%precip,MAX(0.0, met%precip - canopy%wcint))
    ! Add canopy interception to canopy storage term:
    canopy%cansto = canopy%cansto + canopy%wcint
    wetfac = MAX(0.0, MIN(1.0, &
         (ssoil%wb(:,1) - soil%swilt) / (soil%sfc - soil%swilt)))
    !  temporay fixer for accounting of reduction of soil evaporation due to freezing
    wetfac = wetfac * ((1.0-ssoil%wbice(:,1)/ssoil%wb(:,1)))**2
    zetar(:,1) = zeta0 ! stability correction terms
    zetar(:,2) = zetpos + 1
    xdleaf2 = SPREAD(veg%dleaf, 2, mf) ! characteristic leaf length
    dsatdk2 = SPREAD(air%dsatdk, 2, mf)! deriv of sat vap pressure wrt temp
    ca2 = SPREAD(met%ca, 2, mf)        ! CO2 concentration
    csx = ca2                     ! initialise leaf surface CO2 concentration
    da2 = SPREAD(met%da, 2, mf)   ! water vapour pressure deficit
    dsx = da2                     ! init. leaf surface vpd
    tair2 = SPREAD(met%tc, 2, mf) ! air temp in C
    tss2 = SPREAD(ssoil%tss, 2, mf) 
    ejmax2 = SPREAD(veg%ejmax*phenps, 2,mf) !max. pot. electr transp. rate top leaf(mol/m2s)
    vcmax2 = SPREAD(veg%vcmax*phenps, 2,mf) !max. RuBP carboxylsation rate top leaf(mol/m2s)
    tlfx = tair2  ! initialise leaf temp iteration memory variable
    tlfy = tair2  ! initialise current leaf temp
    frac42 = SPREAD(veg%frac4, 2, mf) ! frac C4 plants
    ! weight min stomatal conductance by C3 an C4 plant fractions
    ! Uses undefined radiation variables
    ! gswmin = rad%scalex * (gsw03 * (1. - frac42) + gsw04 * frac42)
    ! Use undefined radiaton values - mrd
!!$    hcx = 0.0       ! init sens heat iteration memory variable
!!$    ecx = rad%rniso ! init lat heat iteration memory variable
!!$    rnx = rad%rniso ! init net rad iteration memory variable
!!$    rny = rad%rniso ! init current estimate net rad
!!$    hcy = 0.0       ! init current estimate lat heat
!!$    ecy = rny - hcy ! init current estimate lat heat
    rdy = 0.0       ! init daytime leaf respiration rate
    rdx = 0.0       ! init daytime leaf respiration rate
    an_y = 0.0      ! init current estimate net photos.
    gswx = 1e-3     ! default stomatal conuctance 
    gbhf = 1e-3     ! default free convection boundary layer conductance
    gbhu = 1e-3     ! default forced convection boundary layer conductance
    anx = 0.0       ! init net photos. iteration memory variable
    ancj = 0.0    
    psycst = SPREAD(air%psyc, 2, mf) ! modified psyc. constant
    ! add on by ypw 1-oct-2002
    gw = 1.0e-3 ! default values of conductance
    gh = 1.0e-3
    ghr= 1.0e-3
    gwwet = 1.0e-3
    ghwet = 1.0e-3
    ghrwet= 1.0e-3
    met%tvair = met%tk
    met%tvrad = met%tk
    met%qvair = met%qv
    ortsoil = ssoil%rtsoil
    ssoil%tss =  (1-ssoil%isflag)*ssoil%tgg(:,1) + ssoil%isflag*ssoil%tggsn(:,1)
    tss4 = ssoil%tss**4
    DO iter = 1, niter
       CALL define_air (met, air)
       psycst = SPREAD(air%psyc, 2, mf)
       dsatdk2 = SPREAD(air%dsatdk, 2, mf)
       CALL radiation(bal, soil, ssoil, veg, air, met, rad)
       ! Restore these - mrd
       hcx = 0.0       ! init sens heat iteration memory variable
       ecx = rad%rniso ! init lat heat iteration memory variable
       rnx = rad%rniso ! init net rad iteration memory variable
       rny = rad%rniso ! init current estimate net rad
       hcy = 0.0       ! init current estimate lat heat
       ecy = rny - hcy ! init current estimate lat heat

       gswmin = rad%scalex * (gsw03 * (1. - frac42) + gsw04 * frac42)
       ! AERODYNAMIC PROPERTIES: friction velocity us, thence turbulent
       ! resistances rt0, rt1 (elements of dispersion matrix):
       ! See CSIRO SCAM, Raupach et al 1997, eq. 3.46:
       canopy%us = MAX(1.e-6, &
            vonk * MAX(met%ua,umin) / ( &
            LOG(rough%zref / rough%z0m) - &
            psim(zetar(:,iter)) + &
            psim(zetar(:,iter) * rough%z0m / rough%zref) ))
       ! Turbulent aerodynamic resistance from roughness sublayer depth to reference height,
       ! x=1 if zref+disp>zruffs, 0 otherwise: thus rt1usc = 0 if zref+disp<zruffs
       ! See CSIRO SCAM, Raupach et al 1997, eq. 3.53:
       xx = 0.5 + sign(0.5,rough%zref+rough%disp-rough%zruffs)
       rt1usc = xx * (LOG(rough%zref/MAX(rough%zruffs-rough%disp, rough%z0soilsn)) &
            - psis(zetar(:,iter)) &
            +  psis(zetar(:,iter)*(rough%zruffs-rough%disp)/rough%zref) )/vonk
       ! rt0 = turbulent resistance from soil to canopy:
       rt0 = rough%rt0us / canopy%us
       ! Aerodynamic resistance (sum 3 height integrals)/us
       ! See CSIRO SCAM, Raupach et al 1997, eq. 3.50:
       rough%rt1 = max(5.,(rough%rt1usa + rough%rt1usb + rt1usc) / canopy%us)
       WHERE (ssoil%tss .le. tfrz) ! 
          rough%rt1 = max(25.,rough%rt1)
       END WHERE
       WHERE (ssoil%snowd > 0.1)
          wetfac = 1.
       END WHERE
       ssoil%rtsoil = rt0 + rough%rt1*(0.5+sign(0.5,0.001-veg%vlaiw))
       WHERE (ssoil%tss .le. tfrz ) ! 
          ssoil%rtsoil = max(25.,ssoil%rtsoil)   
       END WHERE
       WHERE ( ssoil%rtsoil .gt. 2.* ortsoil .or. ssoil%rtsoil .lt. 0.5*ortsoil )
          ssoil%rtsoil = 0.5*(ssoil%rtsoil + ortsoil)
       END WHERE
       ! Vegetation boundary-layer conductance (mol/m2/s)
       ! prandt = kinematic viscosity/molecular diffusivity
       ! See CSIRO SCAM, Raupach et al 1997, eq. 3.12. Top leaf:
       gbvtop = air%cmolar*apol * air%visc / prandt / veg%dleaf *	&
            (canopy%us / MIN(rough%usuh, 0.2) * &
            veg%dleaf / air%visc)**0.5 * prandt**(1.0/3.0) / veg%shelrb
       ! Forced convection boundary layer conductance (see Wang & Leuning 1998, AFM):
       gbhu(:,1) = veg%vlaiw*gbvtop*(EXP(-0.5*rough%coexp) -EXP(-rad%extkb*veg%vlaiw)) / &
            (rad%extkb*veg%vlaiw-0.5*rough%coexp)
       gbhu(:,2) = (2.0/rough%coexp)*veg%vlaiw*gbvtop*(1.0-EXP(-0.5*rough%coexp))-gbhu(:,1)
       gaw = air%cmolar / rough%rt1
       WHERE (veg%meth > 0 )
          gaw=100000.0
       END WHERE
       gaw2 = SPREAD(gaw, 2, mf)
       abs_deltlf = 999.0
       deltlfy = 999.0
       DO k=1,mp
          DO kk=1,mf
             IF(rad%fvlai(k,kk) <=1.0e-3) then
                abs_deltlf(k,kk)=0.0
                hcx(k,kk) = 0.0
                ecx(k,kk) = 0.0
                anx(k,kk) = 0.0
                rnx(k,kk) = 0.0
                rny(k,kk) = rnx(k,kk)
                hcy(k,kk) = hcx(k,kk)
                ecy(k,kk) = ecx(k,kk)
                rdy(k,kk) = rdx(k,kk)
                an_y(k,kk) = anx(k,kk)
              ENDIF
          ENDDO
       ENDDO
       deltlfy = abs_deltlf

       k = 0
       DO WHILE (ANY(abs_deltlf > 0.1)  .AND.  k < maxiter)
          k = k + 1
#ifdef sumdd
          WHERE (rad%fvlai > 1e-3 .and. abs_deltlf > 0.1)
#else
          WHERE (rad%fvlai > 1e-3)
#endif
             ! Grashof number (Leuning et al, 1995) eq E4:
             gras = max(1.0e-6,1.595E8*ABS(tlfx-tair2)*(xdleaf2**3.))
             ! See Appendix E in (Leuning et al, 1995):
             gbhf = rad%fvlai*SPREAD(air%cmolar, 2, mf)*0.5*dheat *(gras**0.25)/xdleaf2
             gh = 1.0/(MIN(1e3, SPREAD(1.0/gaw, 2, mf) + 0.5/(gbhu+gbhf)))
             ghr = rad%gradis+gh
             temp =  xvcmxt3(tlfx+tfrz)
             !  Leuning 2002 (P C & E) equation for temperature response
             !  used for Vcmax for C3 plants:
             vcmxt3 = (1.0-frac42)*vcmax2*rad%scalex *temp
             temp=  xvcmxt4(tlfx)
             ! Temperature of Vcmax for C4 plants (Collatz et al 1989):
             vcmxt4 = frac42 * vcmax2 * rad%scalex * temp
             temp= xejmxt3(tlfx+tfrz)
             !  Leuning 2002 (P C & E) equation for temperature response
             !  used for Jmax for C3 plants:
             ejmxt3 = (1.0-frac42) * ejmax2 * rad%scalex * temp
             tdiff  =  tlfx+tfrz-trefk
             conkct = conkc0*EXP((ekc/(rgas* trefk)) *(1.-trefk/(tlfx+tfrz)))
             conkot = conko0*EXP((eko/(rgas* trefk)) *(1.-trefk/(tlfx+tfrz)))
             cx(:,:,1) = conkct*(1.0+0.21/conkot)
             cx(:,:,2) = 2.0* gam0*(1.+gam1*tdiff + gam2*tdiff*tdiff) !gamma*
             vx3(:,:,1) = vcmxt3
             vx4(:,:,1) = vcmxt4
             temp = rad%qcan(:,:,1)*jtomol*(1.0-frac42)
             vx3(:,:,2) = ej3x(temp,ejmxt3)
             temp = frac42*rad%qcan(:,:,1)*jtomol
             vx4(:,:,2) = ej4x(temp,vcmxt4)
             rdx = (cfrd3*vcmxt3+cfrd4*vcmxt4)*SPREAD(fwsoil, 2, mf)
             xleuning = (1.0-frac42)*a1c3/(1.0+dsx/d0c3) +frac42*a1c4/(1.0+dsx/d0c4)
             xleuning = xleuning * SPREAD(fwsoil, 2, mf) / (csx-co2cp3)
             ! Rubisco limited:
             coef2(:,:,1) = gswmin/rgswc+xleuning *(vx3(:,:,1)-(rdx-vx4(:,:,1)))
             coef1(:,:,1) = (1.0-csx*xleuning) *(vx3(:,:,1)+vx4(:,:,1)-rdx)	&
                  +(gswmin/rgswc)*(cx(:,:,1)-csx) -xleuning*(vx3(:,:,1)*cx(:,:,2)/2.0 &
                  +cx(:,:,1)*(rdx-vx4(:,:,1)))
             coef0(:,:,1) = -(1.0-csx*xleuning) *(vx3(:,:,1)*cx(:,:,2)/2.0  &
                  +cx(:,:,1)*(rdx-vx4(:,:,1))) -(gswmin/rgswc)*cx(:,:,1)*csx
             delcx(:,:,1) = coef1(:,:,1)**2 -4.0*coef0(:,:,1)*coef2(:,:,1)
             ci(:,:,1) = (-coef1(:,:,1)+SQRT(MAX(0.0_r_2,delcx(:,:,1)))) /(2.0*coef2(:,:,1))
             ci(:,:,1) = MAX(0.0_r_2,ci(:,:,1))
             ancj(:,:,1) = vx3(:,:,1)*(ci(:,:,1)-cx(:,:,2)/2.0)	&
                  / (ci(:,:,1) + cx(:,:,1)) + vx4(:,:,1) - rdx
             ! RuBP limited:
             coef2(:,:,2) = gswmin/rgswc+xleuning *(vx3(:,:,2)-(rdx-vx4(:,:,2)))
             coef1(:,:,2) = (1.0-csx*xleuning) *(vx3(:,:,2)+vx4(:,:,2)-rdx)	&
                  +(gswmin/rgswc)*(cx(:,:,2)-csx) -xleuning*(vx3(:,:,2)*cx(:,:,2)/2.0 &
                  +cx(:,:,2)*(rdx-vx4(:,:,2)))
             coef0(:,:,2) = -(1.0-csx*xleuning) *(vx3(:,:,2)*cx(:,:,2)/2.0  &
                  +cx(:,:,2)*(rdx-vx4(:,:,2))) -(gswmin/rgswc)*cx(:,:,2)*csx
             delcx(:,:,2) = coef1(:,:,2)**2 -4.0*coef0(:,:,2)*coef2(:,:,2)
             ci(:,:,2) = (-coef1(:,:,2)+SQRT(MAX(0.0_r_2,delcx(:,:,2)))) /(2.0*coef2(:,:,2))
             ci(:,:,2) = MAX(0.0_r_2,ci(:,:,2))
             ancj(:,:,2) = vx3(:,:,2)*(ci(:,:,2)-cx(:,:,2)/2.0)	&
                  /(ci(:,:,2)+cx(:,:,2)) +vx4(:,:,2)-rdx
             ! Sink limited:
             coef2(:,:,3) = xleuning
             coef1(:,:,3) = gswmin/rgswc + xleuning * (rdx - 0.5*vcmxt3)  +  &
                  effc4 * vcmxt4 - xleuning * csx * effc4 *vcmxt4
             coef0(:,:,3) = -(gswmin/rgswc)*csx *effc4*vcmxt4 +	&
                  (rdx -0.5*vcmxt3)*gswmin/rgswc
             delcx(:,:,3) = coef1(:,:,3)**2 -4.0*coef0(:,:,3)*coef2(:,:,3)
             ancj(:,:,3)  = (-coef1(:,:,3)+SQRT(MAX(0.0_r_2,delcx(:,:,3)))) &
                  /(2.0*coef2(:,:,3))
             anx = MIN(ancj(:,:,1),ancj(:,:,2),ancj(:,:,3))
             csx = ca2 - anx * (1.0/gaw2+rgbwc/(gbhu + gbhf))
             gswx = gswmin+MAX(0.0,rgswc*xleuning *anx)
             gw = 1.0/(1.0/gswx + 1.0/(1.075*(gbhu+gbhf)) + SPREAD(1.0/gaw, 2, mf))
             psycst = SPREAD(air%psyc, 2, mf) *ghr/gw
             tlfxx = tlfx
             ecx = (dsatdk2*rad%rniso +capp*rmair*da2*ghr) /(dsatdk2+psycst)

             hcx = (rad%rniso-ecx)*gh/ghr
             tlfx=tair2+hcx/(capp*rmair*gh)
!             tlfx=max(tlfx,min(tss2,tair2)-3.)
!             tlfx=min(tlfx,max(tss2,tair2)+3.)

             rnx = rad%rniso-capp*rmair*(tlfx -tair2)*rad%gradis
             dsx = ecx*100.0* SPREAD(met%pmb, 2, mf) /(gswx*rmh2o*SPREAD(air%rlam, 2, mf))
             dsx = da2 + dsatdk2 * (tlfx-tair2)
             deltlf = tlfxx-tlfx
             abs_deltlf = ABS(deltlf)
          END WHERE
          WHERE (abs_deltlf > 0.1 .AND. abs_deltlf < ABS(deltlfy) )
             deltlfy = deltlf
             tlfy = tlfx
             rny = rnx
             hcy = hcx
             ecy = ecx
             rdy = rdx
             an_y = anx
          END WHERE
          WHERE (abs_deltlf > 0.1)
             !        after four iteration, take the mean value of current and previous estimates
             !        as the next estimate of leaf temperature, to avoid oscillation
             tlfx = (0.5*(MAX(0,k-5)/(k-4.9999))) *tlfxx + &
                  (1.0- (0.5*(MAX(0,k-5)/(k-4.9999))))*tlfx
          END WHERE
          IF(k==1) THEN
             !        taken the first iterated estimates as the defaults
             tlfy = tlfx
             rny = rnx
             hcy = hcx
             ecy = ecx
             rdy = rdx
             an_y = anx
          END IF
       END DO  ! DO WHILE (ANY(abs_deltlf > 0.1)	.AND.  k < maxiter)

       ! VEGETATION SENSIBLE AND LATENT HEAT FLUXES fevw, fhvw (W/m2) for a wet canopy
       ! calculate total thermal resistance, rthv in s/m
       ghwet=gaw*SUM(gbhu,2)/(0.5*gaw+SUM(gbhu,2))
       gwwet=1.075*SUM(gbhu,2)*gaw/(1.075*SUM(gbhu,2)+gaw)
       WHERE (veg%meth > 0 )
          ghwet=2.*SUM(gbhu,2)
          gwwet=1.075*SUM(gbhu,2)
       END WHERE
       ghrwet=SUM(rad%gradis,2)+ghwet
       ! Calculate fraction of canopy which is wet:
       veg%fwet   = max(0.0,min(1.0,0.8*canopy%cansto/cansat))
       ! Calculate lat heat from wet canopy, may be neg. if dew onto wet canopy
       ! to avoid excessive evaporation:
       ccfevw = MIN( canopy%cansto*air%rlam/dels, 2./(1440./(dels/60.))*air%rlam)
       canopy%fevw = MIN(veg%fwet*((air%dsatdk*SUM(rad%rniso,2)+ &
            capp*rmair*met%da*ghrwet) &
            /(air%dsatdk+air%psyc*ghrwet/gwwet)), ccfevw)
       ! Calculate sens heat from wet canopy:
       canopy%fhvw = (veg%fwet*SUM(rad%rniso,2)-canopy%fevw)*ghwet/ghrwet
       !
       ! calculate (dry) canopy transpiration, may be negative if dew
       canopy%fevc = (1.0 - veg%fwet) * sum(ecy,2)
       evapfbl = 0.
       DO k = 1,ms
          WHERE (canopy%fevc > 0.)
             evapfb =canopy%fevc  * dels/air%rlam		 ! convert to mm/dt
             evapfbl(:,k) =min(evapfb*soil%froot(:,k),max(0.,min(ssoil%wb(:,k)-soil%swilt, & 
                  ssoil%wb(:,k)-1.05*ssoil%wbice(:,k)))*soil%zse(k)*1000.)
          END WHERE
       END DO
       canopy%fevc = 0.
       DO k = 1,ms
          canopy%fevc=canopy%fevc+ evapfbl(:,k)*air%rlam/dels
       END DO
       ! Calculate latent heat from vegetation:
       canopy%fev = canopy%fevc + canopy%fevw
       ! Calculate sensible heat from vegetation:
       canopy%fhv = (1.0 - veg%fwet) * sum(hcy,2)  + canopy%fhvw
       ! Calculate net rad absorbed by canopy:
       canopy%fnv = (1.0-veg%fwet)*SUM(rny,2)+canopy%fevw+canopy%fhvw
       ! canopy radiative temperature is calculated based on long-wave radiation balance
       ! Q_lw=Q_lw_iso - (1.0-fwet)*SUM(capp*rmair*(tlfy-tair)*gri - canopy%fhvw*gr/ghw
       ! Q_lw=(1-transd)*(L_soil+L_sky-2.0*L_can)
       ! therefore
       ! Q_lw_iso-Q_lw=2(1-transd)*emleaf*(Tv^4-Tc^4)
       !	    rad%lwabv = (1.0-veg%fwet)*(capp*rmair*(tlfy(:,1) - met%tc)*rad%gradis(:,1) &
       !		 +capp*rmair*(tlfy(:,2) - met%tc)*rad%gradis(:,2)) &
       !		 + canopy%fhvw*SUM(rad%gradis,2)/ghwet
       rad%lwabv = (1.0-veg%fwet)*(capp*rmair*(tlfy(:,1) - &
            (met%tk-tfrz))*rad%gradis(:,1) &
            +capp*rmair*(tlfy(:,2) - (met%tk-tfrz))*rad%gradis(:,2)) &
            + canopy%fhvw*SUM(rad%gradis,2)/ghwet
       ! add if condition here to avoid dividing by zero ie when rad%transd=1.0 Ypw:24-02-2003
       WHERE (rad%transd <= 0.98) ! need to avoid transd values approaching 1
          canopy%tv = (rad%lwabv / (2.0*(1.0-rad%transd)*sboltz*emleaf)+met%tk**4)**0.25
       ELSEWHERE ! sparse canopy
          canopy%tv = met%tk
       END WHERE
       canopy%ghflux = (1-ssoil%isflag)*canopy%ghflux + ssoil%isflag*canopy%sghflux
       qstss = qsatf((ssoil%tss - tfrz),met%pmb)
       dq = qstss - met%qv
       !			       excessive dew over snow area
       WHERE (ssoil%snowd > 0.1)
          dq = max( -0.1e-3, dq)
       END WHERE
       ! Calculate net rad to soil:
       canopy%fns = rad%qssabs + rad%transd*met%fld + (1.0-rad%transd)*emleaf* &
            sboltz*canopy%tv**4 - emsoil*sboltz* tss4
       ! Penman-Monteith formula
       !	    sss=air%dsatdk
       !	    cc1=sss/(sss+air%psyc )
       !	    cc2=air%psyc /(sss+air%psyc )
       !           ssoil%potev = cc1 * (canopy%fns - canopy%ghflux) +  &
       !              cc2 * air%rho * air%rlam*(qsatf((met%tk-tfrz),met%pmb) - met%qv)/ssoil%rtsoil 
       ssoil%potev =air%rho * air%rlam * dq /ssoil%rtsoil
       ! Soil latent heat:
       canopy%fes= wetfac * ssoil%potev
       WHERE (ssoil%snowd < 0.1 .and. canopy%fes .gt. 0. )
          canopy%fes= min(canopy%fes,max(0.,(ssoil%wb(:,1)-soil%swilt))* soil%zse(1) &
               * 1000. * air%rlam / dels)
          canopy%fes = min(canopy%fes,(ssoil%wb(:,1)-ssoil%wbice(:,1)) * soil%zse(1) &
               * 1000. * air%rlam / dels)
       END WHERE
       ssoil%cls=1.
       WHERE (ssoil%snowd >= 0.1)
          ssoil%cls = 1.1335
          canopy%fes= min(wetfac * ssoil%potev,ssoil%snowd/dels*air%rlam*ssoil%cls)
       END WHERE
       ! Calculate soil sensible heat:
       canopy%fhs = air%rho*capp*(ssoil%tss - met%tk) /max(ssoil%rtsoil,15.0)
       ! Calculate ground heat flux:
       canopy%ga = canopy%fns-canopy%fhs-canopy%fes*ssoil%cls
       ! Calculate total latent heat:
       canopy%fe = canopy%fev + canopy%fes
       ! Calculate total sensible heat:
       canopy%fh = canopy%fhv + canopy%fhs
       !	   use the dispersion matrix (dm) to find the air temperature and specific humidity
       !	   (raupach, finkele and zhang 1997, pp 17)
       met%tvair = met%tk
       met%qvair = met%qv
       WHERE (veg%meth > 0  .and. rad%transd < 0.95)      ! exclude sparse ******** SIMPLIFY this***
          !      use the dispersion matrix (DM) to find the air temperature and specific humidity 
          !      (Raupach, Finkele and Zhang 1997, pp 17)
          rbw = air%cmolar/sum(gbhu+gbhf,2)
          rsw = air%cmolar/sum(gswx,2)
          dmah = (rt0+rough%rt1)*((1.+air%epsi)/rsw +1.0/rbw) &
               + air%epsi * (rt0*rough%rt1)/(rbw*rsw)
          dmbh = (-air%rlam/capp)*(rt0*rough%rt1)/(rbw*rsw)
          dmch = ((1.+air%epsi)/rsw +1.0/rbw)*rt0*rough%rt1* &
               (canopy%fhv + canopy%fhs)/(air%rho*capp)
          dmae = (-air%epsi*capp/air%rlam)*(rt0*rough%rt1)/(rbw*rsw)
          dmbe = (rt0+wetfac*rough%rt1)*((1.+air%epsi)/rsw +1.0/rbw)+(rt0*rough%rt1)/(rbw*rsw)
          dmce = ((1.+air%epsi)/rsw +1.0/rbw)*rt0*rough%rt1*(canopy%fev + canopy%fes)/ &
               (air%rho*air%rlam)
          met%tvair = met%tk + (dmbe*dmch-dmbh*dmce)/(dmah*dmbe-dmae*dmbh+1.0e-12)
          met%qvair = met%qv + (dmah*dmce-dmae*dmch)/(dmah*dmbe-dmae*dmbh+1.0e-12)
          met%qvair = max(0.0,met%qvair)
       END WHERE
       qstvair = qsatf((met%tvair-tfrz),met%pmb)
       met%dva = (qstvair - met%qvair) *  rmair/rmh2o * met%pmb * 100.
       dva2 = SPREAD(met%dva, 2, mf)
       tvair2 = SPREAD(met%tvair-tfrz, 2, mf)
       met%tvrad = met%tvair
       ! recalculate using canopy within temperature
       !     where (veg%meth .eq. 0 )

       WHERE (rad%fvlai > 1e-3)
          ecy = (dsatdk2*rad%rniso +capp*rmair*dva2*ghr) /(dsatdk2+psycst)
          hcy = (rad%rniso-ecy)*gh/ghr
          !             tlfx=tvair+hcx/(capp*rmair*gh)
          tlfy=tvair2+hcy/(capp*rmair*gh)
!          tlfy=max(tlfy,min(tss2,tair2)-3.)
!          tlfy=min(tlfy,max(tss2,tair2)+3.)
       END WHERE
       WHERE (veg%meth > 0 )
          canopy%fevc = (1.0 - veg%fwet) * sum(ecy,2)
          !     evapfbl = 0.
          !     do k = 1,ms
          WHERE (canopy%fevc > 0.)
             evapfb =canopy%fevc  * dels/air%rlam             ! convert to mm/dt
             evapfbl(:,1) =min(evapfb*soil%froot(:,1),max(0.,min(ssoil%wb(:,1)-soil%swilt, &
                  ssoil%wb(:,1)-1.05*ssoil%wbice(:,1)))*soil%zse(1)*1000.)
             evapfbl(:,2) =min(evapfb*soil%froot(:,2),max(0.,min(ssoil%wb(:,2)-soil%swilt, &
                  ssoil%wb(:,2)-1.05*ssoil%wbice(:,2)))*soil%zse(2)*1000.)
             evapfbl(:,3) =min(evapfb*soil%froot(:,3),max(0.,min(ssoil%wb(:,3)-soil%swilt, &
                  ssoil%wb(:,3)-1.05*ssoil%wbice(:,3)))*soil%zse(3)*1000.)
             evapfbl(:,4) =min(evapfb*soil%froot(:,4),max(0.,min(ssoil%wb(:,4)-soil%swilt, &
                  ssoil%wb(:,4)-1.05*ssoil%wbice(:,4)))*soil%zse(4)*1000.)
             evapfbl(:,5) =min(evapfb*soil%froot(:,5),max(0.,min(ssoil%wb(:,5)-soil%swilt, &
                  ssoil%wb(:,5)-1.05*ssoil%wbice(:,5)))*soil%zse(5)*1000.)
             evapfbl(:,6) =min(evapfb*soil%froot(:,6),max(0.,min(ssoil%wb(:,6)-soil%swilt, &
                  ssoil%wb(:,6)-1.05*ssoil%wbice(:,6)))*soil%zse(6)*1000.)
          END WHERE
          !      enddo
          canopy%fevc=(evapfbl(:,1)+evapfbl(:,2)+evapfbl(:,3)+evapfbl(:,4)+evapfbl(:,5)+evapfbl(:,6))*air%rlam/dels

          !       WHERE ( canopy%fevc > 0.)
          !        evapfb =canopy%fevc  * dels/air%rlam             ! convert to mm/dt
          !        evapfb1=min(evapfb*soil%froot(:,1),max(0.,(ssoil%wb(:,1)-soil%swilt)) &
          !                                                        *soil%zse(1)*1000.)
          !        evapfb2=min(evapfb*soil%froot(:,2),max(0.,(ssoil%wb(:,2)-soil%swilt)) &
          !                                                        *soil%zse(2)*1000.)
          !        evapfb3=min(evapfb*soil%froot(:,3),max(0.,(ssoil%wb(:,3)-soil%swilt)) &
          !                                                        *soil%zse(3)*1000.)
          !        evapfb4=min(evapfb*soil%froot(:,4),max(0.,(ssoil%wb(:,4)-soil%swilt)) &
          !                                                        *soil%zse(4)*1000.)
          !        evapfb5=min(evapfb*soil%froot(:,5),max(0.,(ssoil%wb(:,5)-soil%swilt)) &
          !                                                        *soil%zse(5)*1000.)
          !        evapfb6=min(evapfb*soil%froot(:,6),max(0.,(ssoil%wb(:,6)-soil%swilt)) &
          !                                                        *soil%zse(6)*1000.)
          !        canopy%fevc=(evapfb1+evapfb2+evapfb3+evapfb4+evapfb5+evapfb6)*air%rlam/dels
          !       END WHERE
          canopy%fev  = canopy%fevc + canopy%fevw
          canopy%fhv  = (1.0 - veg%fwet) * sum(hcy,2)  + canopy%fhvw
          rad%lwabv = (1.0-veg%fwet)*(capp*rmair*(tlfy(:,1) - (met%tvair-tfrz))*rad%gradis(:,1) &
               +capp*rmair*(tlfy(:,2) - (met%tvair-tfrz))*rad%gradis(:,2)) &
               + canopy%fhvw*SUM(rad%gradis,2)/ghwet
          WHERE (rad%transd <= 0.98)
             canopy%tv = (rad%lwabv / (2.0*(1.0-rad%transd)*sboltz*emleaf)+met%tvair**4)**0.25
          ELSEWHERE
             ! sparse canopy 
             canopy%tv = met%tvair
          END WHERE
          canopy%ghflux = (1-ssoil%isflag)*canopy%ghflux + ssoil%isflag*canopy%sghflux
          dq = qstss - met%qvair
          WHERE (ssoil%snowd > 0.1)
             dq = max( -0.1e-3, dq)
          END WHERE
          canopy%fns = rad%qssabs + rad%transd*met%fld + (1.0-rad%transd)*emleaf* &
               sboltz*canopy%tv**4 - emsoil*sboltz* tss4
          ssoil%potev =air%rho * air%rlam * dq /ssoil%rtsoil
          canopy%fes= wetfac * ssoil%potev
          WHERE (ssoil%snowd < 0.1 .and. canopy%fes .gt. 0. )
             canopy%fes= min(canopy%fes,max(0.,(ssoil%wb(:,1)-soil%swilt))* soil%zse(1) &
                  * 1000. * air%rlam / dels)
             canopy%fes = min(canopy%fes,(ssoil%wb(:,1)-ssoil%wbice(:,1)) * soil%zse(1) &
                  * 1000. * air%rlam / dels)
          END WHERE
          ssoil%cls=1.
          WHERE (ssoil%snowd >= 0.1)
             ssoil%cls = 1.1335
             canopy%fes= min(wetfac * ssoil%potev,ssoil%snowd/dels*air%rlam*ssoil%cls)
          END WHERE
          canopy%fhs = air%rho*capp*(ssoil%tss - met%tvair) /max(ssoil%rtsoil,15.0)
          canopy%ga = canopy%fns-canopy%fhs-canopy%fes*ssoil%cls
          canopy%fe = canopy%fev + canopy%fes

          canopy%fh = canopy%fhv + canopy%fhs
       END WHERE ! veg%meth > 0

       ! monin-obukhov stability parameter zetar=zref/l
       !	recompute zetar for the next iteration, except on last iteration
       IF (iter < niter) THEN ! dont compute zetar on the last iter
          iterplus = max(iter+1,2)
          zetar(:,iterplus) = -(vonk*grav*rough%zref*(canopy%fh+0.07*canopy%fe))/ &
               (air%rho*capp*met%tk*canopy%us**3)
          ! case niter=2: final zetar=zetmul*zetar(2) (compute only when iter=1)
          IF (niter == 2) THEN
             zetar(:,2) = zetmul * zetar(:,2)
             WHERE (met%fsd ==  0.0)
                zetar(:,2) = 0.5 * zetar(:,2)
             END WHERE
          END IF
          !	constrain zeta to zetpos and zetneg (set in param0)
          zetar(:,iterplus) = min(zetpos,zetar(:,iterplus))	 ! zetar too +
          zetar(:,iterplus) = max(zetneg,zetar(:,iterplus))	 ! zetar too -
       END IF
    END DO	     ! do iter = 1, niter
    !		      screen temp., windspeed and relative humidity at 1.8m
    tstar = - canopy%fh / ( air%rho*capp*canopy%us)
    qstar = - canopy%fe / ( air%rho*air%rlam *canopy%us)
    zscrn = max(rough%z0m,1.8-rough%disp)
    denom = ( log(rough%zref/zscrn)- psim(zetar(:,iterplus)) + &
         psim(zetar(:,iterplus) * zscrn / rough%zref) ) /vonk
    canopy%tscrn = met%tc - tstar * denom
    rsts = qsatf(canopy%tscrn, met%pmb)
    qtgnet = rsts * wetfac - met%qv
    canopy%cduv = canopy%us * canopy%us / max(met%ua,umin)
    WHERE (qtgnet .gt. 0. )
       qsurf = rsts * wetfac
    ELSEWHERE
       qsurf = .1*rsts*wetfac + .9*met%qv
    END WHERE
    canopy%qscrn = qsurf + qstar * denom
    canopy%uscrn = max(0., max(met%ua,umin) - canopy%us * denom )	 ! at present incorrect
    avgwrs = sum(soil%froot * ssoil%wb,2)
    avgtrs = max(0.0,sum(soil%froot * ssoil%tgg,2)-tfrz)
    poolcoef1=(sum(spread(bgc%ratecp,1,mp)*bgc%cplant,2) - &
         bgc%ratecp(1)*bgc%cplant(:,1))
    poolcoef1w=(sum(spread(bgc%ratecp,1,mp)*bgc%cplant,2) -  &
         bgc%ratecp(1)*bgc%cplant(:,1) - bgc%ratecp(3)*bgc%cplant(:,3))
    poolcoef1r=(sum(spread(bgc%ratecp,1,mp)*bgc%cplant,2) -  &
         bgc%ratecp(1)*bgc%cplant(:,1) - bgc%ratecp(2)*bgc%cplant(:,2))
    ! Carbon uptake from photosynthesis: 
    canopy%frp = veg%rp20*((3.22-0.046*met%tc)**(0.1*(met%tc-20.))) &
         * poolcoef1 /(365.0*24.0*3600.0)		 ! 24/05
    canopy%frpw = veg%rp20*((3.22-0.046*met%tc)**(0.1*(met%tc-20.))) &
         * poolcoef1w /(365.0*24.0*3600.0)		  ! 24/05
    canopy%frpr = veg%rp20*((3.22-0.046*met%tc)**(0.1*(met%tc-20.))) &
         * poolcoef1r /(365.0*24.0*3600.0)		  ! 24/05

    ! This section to be updated as part of carbon module upgrade;
    ! frs is currently calculated in carbon module.
    !canopy%frs  = rsoil(soil%rs20, avgwrs, avgtrs)
    !canopy%frs  = canopy%frs &
    !     * sum(spread(bgc%ratecs,1, mp) * bgc%csoil,2)	&
    !     /(365.0*24.0*3600.0)		     !convert 1/year to 1/second
    !WHERE (ssoil%snowd > 1.)
    !   canopy%frs	= canopy%frs / min(100.,ssoil%snowd)
    !END WHERE
    canopy%frday = 12.0 * sum(rdy, 2)
    canopy%fpn = -12.0 * sum(an_y, 2)
    ! Calculate dewfall: from negative lh wet canopy + neg. lh dry canopy:
    canopy%dewmm = - (min(0.0,canopy%fevw) + min(0.0,canopy%fevc)) * &
         dels * 1.0e3 / (rhow*air%rlam)
    ! Add dewfall to canopy water storage:
    canopy%cansto = canopy%cansto + canopy%dewmm
    ! Calculate canopy water storage excess:
    canopy%spill=max(0.,min(0.2*canopy%cansto,max(0.0, canopy%cansto-cansat)))
    ! Move excess canopy water to throughfall:
    canopy%through = canopy%through + canopy%spill
    ! Initialise 'throughfall to soil' as 'throughfall from canopy'; snow may absorb
    canopy%precis = canopy%through
    ! Update canopy storage term:
    canopy%cansto=canopy%cansto - canopy%spill
    ! Modify canopy water storage for evaporation:
    canopy%cansto = max(canopy%cansto-max(0.0,canopy%fevw)*dels*1.0e3/ &
         (rhow*air%rlam), 0.0)
    ! Calculate the total change in canopy water store (mm/dels):
    canopy%delwc = canopy%cansto-oldcansto
    ! calculate dgdtg, derivative of ghflux
    ssoil%dfn_dtg = (-1.)*4.*emsoil*sboltz*tss4/ssoil%tss	     ! d(canopy%fns)/d(ssoil%tgg)
    ssoil%dfh_dtg = air%rho*capp/ max(ssoil%rtsoil,15.0)	   ! d(canopy%fhs)/d(ssoil%tgg)
    ssoil%dfe_ddq = wetfac*air%rho*air%rlam/max(ssoil%rtsoil,15.0)	! d(canopy%fes)/d(dq)
    ssoil%ddq_dtg = (rmh2o/rmair)/met%pmb *tetena*tetenb*tetenc &
         /((tetenc+ssoil%tss-tfrz)**2)*exp(tetenb*(ssoil%tss-tfrz)/(tetenc+ssoil%tss-tfrz))
    canopy%dgdtg = ssoil%dfn_dtg - ssoil%dfh_dtg - ssoil%dfe_ddq * ssoil%ddq_dtg
    !ypw: energy balance of the dry canopy
!    bal%drybal=ecy(:,1)+ecy(:,2)+hcy(:,1)+hcy(:,2)-rad%rniso(:,1)-rad%rniso(:,2) &
!         +capp*rmair*(tlfy(:,1)-(met%tvair-tfrz))*rad%gradis(:,1) &
!         +capp*rmair*(tlfy(:,2)-(met%tvair-tfrz))*rad%gradis(:,2)
    bal%drybal=ecy(:,1)+hcy(:,1)-rad%rniso(:,1) &
         +capp*rmair*(tlfy(:,1)-(met%tvair-tfrz))*rad%gradis(:,1)

    bal%drybal=ecy(:,2)+hcy(:,2)-rad%rniso(:,2) &
         +capp*rmair*(tlfy(:,2)-(met%tvair-tfrz))*rad%gradis(:,2)

    !ypw: energy balance of the wet canopy
    bal%wetbal=canopy%fevw+canopy%fhvw-(rad%rniso(:,1)+rad%rniso(:,2))*veg%fwet &
         +canopy%fhvw*(rad%gradis(:,1)+rad%gradis(:,2))/ghwet

  CONTAINS
    !--------------------------------------------------------------------------
    ELEMENTAL FUNCTION qsatf(tair,pmb) RESULT(r)
      ! MRR, 1987
      ! AT TEMP tair (DEG C) AND PRESSURE pmb (MB), GET SATURATION SPECIFIC
      ! HUMIDITY (KG/KG) FROM TETEN FORMULA
      REAL(r_1), INTENT(IN) :: tair ! air temperature (C)
      REAL(r_1), INTENT(IN) :: pmb  ! pressure PMB (mb)
      REAL(r_1)		  :: r    ! result; sat sp humidity
      r = (rmh2o/rmair) * (tetena*EXP(tetenb*tair/(tetenc+tair))) / pmb
    END FUNCTION qsatf
    !---------------------------------------------------------
    ELEMENTAL FUNCTION ej3x(parx,x) result(z)
      REAL(r_1), INTENT(IN)	:: parx
      REAL(r_1), INTENT(IN)	:: x
      REAL(r_1)			:: z
      z = max(0.0, &
           0.25*((alpha3*parx+x-sqrt((alpha3*parx+x)**2 - &
           4.0*convx3*alpha3*parx*x)) /(2.0*convx3)) )
    END FUNCTION ej3x
    !---------------------------------------------------------
    ELEMENTAL FUNCTION ej4x(parx,x) result(z)
      REAL(r_1), INTENT(IN)	:: parx
      REAL(r_1), INTENT(IN)	:: x
      REAL(r_1)			:: z
      z = max(0.0, &
           (alpha4*parx+x-sqrt((alpha4*parx+x)**2 - &
           4.0*convx4*alpha4*parx*x))/(2.0*convx4))
    END FUNCTION ej4x
    !---------------------------------------------------------
    ELEMENTAL FUNCTION xvcmxt4(x) result(z)
      REAL(r_1), PARAMETER	:: q10c4 = 2.0
      REAL(r_1), INTENT(IN)	:: x
      REAL(r_1)			:: z
      z = q10c4 ** (0.1 * x - 2.5) / &
           ((1.0 + exp(0.3 * (13.0 - x))) * (1.0 + exp(0.3 * (x - 36.0))))
    END FUNCTION xvcmxt4
    !---------------------------------------------------------
    ELEMENTAL FUNCTION xvcmxt3(x) result(z)
      !  leuning 2002 (p c & e) equation for temperature response
      !  used for vcmax for c3 plants
      REAL(r_1), INTENT(IN)	:: x
      REAL(r_1)			:: xvcnum
      REAL(r_1)			:: xvcden
      REAL(r_1)			:: z
      xvcnum=xvccoef*exp((ehavc/(rgas*trefk))*(1.-trefk/x))
      xvcden=1.0+exp((entropvc*x-ehdvc)/(rgas*x))
      z = max(0.0,xvcnum/xvcden)
    END FUNCTION xvcmxt3
    !---------------------------------------------------------
    ELEMENTAL FUNCTION xejmxt3(x) result(z)
      !  leuning 2002 (p c & e) equation for temperature response
      !  used for jmax for c3 plants
      REAL(r_1), INTENT(IN)	:: x
      REAL(r_1)			:: xjxnum
      REAL(r_1)			:: xjxden
      REAL(r_1)			:: z
      xjxnum=xjxcoef*exp((ehajx/(rgas*trefk))*(1.-trefk/x))
      xjxden=1.0+exp((entropjx*x-ehdjx)/(rgas*x))
      z = max(0.0, xjxnum/xjxden)
    END FUNCTION xejmxt3
    !---------------------------------------------------------
    ELEMENTAL FUNCTION psim(zeta) result(r)
      ! mrr, 16-sep-92 (from function psi: mrr, edinburgh 1977)
      ! computes integrated stability function psim(z/l) (z/l=zeta)
      ! for momentum, using the businger-dyer form for unstable cases
      ! and the webb form for stable cases. see paulson (1970).
      USE math_constants
      REAL(r_1), INTENT(IN)	:: zeta
      REAL(r_1)			:: r
      REAL(r_1)			:: x
      REAL(r_1), PARAMETER	:: gu = 16.0
      REAL(r_1), PARAMETER	:: gs = 5.0
      x = (1.0 + gu*abs(zeta))**0.25
      r = merge(log((1.0+x*x)*(1.0+x)**2/8.0) - 2.0*atan(x) &
           + pi*0.5, -gs*zeta, zeta < 0.0)
    END FUNCTION psim
    !---------------------------------------------------------
    ELEMENTAL FUNCTION psis(zeta) result(r)
      ! mrr, 16-sep-92 (from function psi: mrr, edinburgh 1977)
      ! computes integrated stability function psis(z/l) (z/l=zeta)
      ! for scalars, using the businger-dyer form for unstable cases
      ! and the webb form for stable cases. see paulson (1970).
      REAL(r_1), INTENT(IN)	:: zeta
      REAL(r_1)			:: r
      REAL(r_1), PARAMETER	:: gu = 16.0
      REAL(r_1), PARAMETER	:: gs = 5.0
      r = merge(2.0 * log((1.0 + sqrt(1.0 + gu * abs(zeta))) * 0.5), &
           - gs * zeta, zeta < 0.0)
    END FUNCTION psis
    !---------------------------------------------------------
    ELEMENTAL FUNCTION rplant(rpconst, rpcoef, tair) result(z)
      REAL(r_1), INTENT(IN)	:: rpconst
      REAL(r_1), INTENT(IN)	:: rpcoef
      REAL(r_1), INTENT(IN)	:: tair
      REAL(r_1)			:: z
      z = rpconst * exp(rpcoef * tair)
    END FUNCTION rplant
    !---------------------------------------------------------
    ELEMENTAL FUNCTION rsoil(rsconst, avgwrs, avgtrs) result(z)
      REAL(r_1), INTENT(IN)	:: rsconst
      REAL(r_1), INTENT(IN)	:: avgwrs
      REAL(r_1), INTENT(IN)	:: avgtrs
      REAL(r_1)			:: z
      z = rsconst * min(1.0, max(0.0, min(&
           -0.0178+0.2883*avgwrs+5.0176*avgwrs*avgwrs-4.5128*avgwrs*avgwrs*avgwrs, &
           0.3320+22.6726*exp(-5.8184*avgwrs)))) &
           * min(1.0, max(0.0, min( 0.0104*(avgtrs**1.3053), 5.5956-0.1189*avgtrs)))
    END FUNCTION rsoil
    !---------------------------------------------------------
  END SUBROUTINE define_canopy
END MODULE canopy_module
!================================================================================
MODULE cbm_module
  USE canopy_module
  IMPLICIT NONE
  PRIVATE
  PUBLIC cbm 
CONTAINS
  SUBROUTINE cbm(ktau, kstart, kend, ktauyear, dels, air, bgc, canopy, met, &
       bal, rad, rough, soil, ssoil, sum_flux, veg)
    USE carbon_module
    USE soil_snow_module
    USE define_types
    USE physical_constants
    USE roughness_module
    USE radiation_module
    INTEGER(i_d) :: k  
    INTEGER(i_d), INTENT(IN)		:: ktau ! integration step number
    INTEGER(i_d), INTENT(IN)	       	:: kstart ! starting value of ktau
    INTEGER(i_d), INTENT(IN)	       	:: kend ! total # timesteps in run
    INTEGER(i_d), INTENT(IN)	       	:: ktauyear
    REAL(r_1), INTENT(IN)		:: dels ! time setp size (s)
    TYPE (air_type), INTENT(INOUT)	:: air
    TYPE (bgc_pool_type), INTENT(INOUT)	:: bgc	
    TYPE (canopy_type), INTENT(INOUT)	:: canopy
    TYPE (met_type), INTENT(INOUT) 	:: met
    TYPE (balances_type), INTENT(INOUT) 	:: bal
    TYPE (radiation_type), INTENT(INOUT) 	:: rad
    TYPE (roughness_type), INTENT(INOUT) 	:: rough
    TYPE (soil_parameter_type), INTENT(INOUT)	:: soil	
    TYPE (soil_snow_type), INTENT(INOUT)	:: ssoil
    TYPE (sum_flux_type), INTENT(INOUT)	:: sum_flux
    TYPE (veg_parameter_type), INTENT(INOUT)	:: veg	
    INTEGER(i_d) :: ijd

    veg%meth = 0
    ijd =3688

    ssoil%albsoilsn(:,3) = 0.05
    CALL ruff_resist(veg, rough, ssoil)
    CALL init_radiation(rad,veg)   ! need to be called at every dt
    ! Calculate canopy variables:
    CALL define_canopy(bal,rad,rough,air,met,dels,ssoil,soil,veg,bgc,canopy)

    CALL soil_snow(dels, ktau, soil, ssoil, canopy, met)

    canopy%fev	= canopy%fevc + canopy%fevw
    canopy%fe = canopy%fev + canopy%fes
    canopy%rnet = canopy%fns + canopy%fnv
    rad%trad = ( (1.-rad%transd)*canopy%tv**4 + rad%transd * ssoil%tss**4 )**0.25
    ! Several of these sums are never initialised properly anywhere else
    ! These ones are never initialised at all - mrd
    sum_flux%sumrpw = 0.
    sum_flux%sumrpr = 0.
    sum_flux%dsumpn = 0.
    sum_flux%dsumrp = 0.
    sum_flux%dsumrd = 0.

    sum_flux%sumpn = sum_flux%sumpn+canopy%fpn*dels
    sum_flux%sumrp = sum_flux%sumrp+canopy%frp*dels
    sum_flux%sumrpw = sum_flux%sumrpw+canopy%frpw*dels
    sum_flux%sumrpr = sum_flux%sumrpr+canopy%frpr*dels
    sum_flux%sumrd = sum_flux%sumrd+canopy%frday*dels
    sum_flux%dsumpn = sum_flux%dsumpn+canopy%fpn*dels
    sum_flux%dsumrp = sum_flux%dsumrp+canopy%frp*dels
    sum_flux%dsumrd = sum_flux%dsumrd+canopy%frday*dels
    rad%flws = sboltz*emsoil* ssoil%tss **4
    
    CALL soilcarb(soil, ssoil, veg, bgc, met, canopy)
    CALL carbon_pl(dels, soil, ssoil, veg, canopy, bgc)
    ! canopy%frs set in soilcarb
    sum_flux%sumrs = sum_flux%sumrs+canopy%frs*dels
    ! Set net ecosystem exchange after adjustments to frs:
    canopy%fnee = canopy%fpn + canopy%frs + canopy%frp
  
END SUBROUTINE cbm

END MODULE cbm_module

!===================================================================================
