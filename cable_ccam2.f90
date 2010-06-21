module cable_ccam

  ! CABLE interface originally developed by the CABLE group
  ! Subsequently modified by MJT for mosaic and new radiation scheme

  ! ivegt   type
  ! 1       Evergreen Needleleaf Forest
  ! 2       Evergreen Broadleaf Forest
  ! 3       Deciduous Needleaf Forest
  ! 4       Deciduous Broadleaf Forest
  ! 5       Mixed Forest
  ! 6       Closed Shrublands
  ! 7       Open Shrublands
  ! 8       Woody Savannas
  ! 9       Savannas
  ! 10      Grasslands
  ! 11      Permanent Wetlands
  ! 12      Croplands
  ! 13      Urban and Built-up
  ! 14      Cropland/Natural Vegetation Mosaic
  ! 15      Snow and Ice
  ! 16      Barren or Sparsely Vegetated
  ! 17      Water Bodies
  
  ! isoilm  type
  ! 0       water/ocean
  ! 1       coarse               sand/loamy_sand
  ! 2       medium               clay-loam/silty-clay-loam/silt-loam
  ! 3       fine                 clay
  ! 4       coarse-medium        sandy-loam/loam
  ! 5       coarse-fine          sandy-clay
  ! 6       medium-fine          silty-clay 
  ! 7       coarse-medium-fine   sandy-clay-loam
  ! 8       organi!              peat
  ! 9       land ice

  USE define_dimensions, cbm_ms => ms
  use cab_albedo_module
  USE canopy_module
  USE carbon_module
  USE soil_snow_module
  USE define_types
  USE physical_constants
  USE roughness_module
  USE radiation_module
  USE air_module

  private
  public CABLE,sib4,loadcbmparm,savetile

  integer, parameter :: CABLE = 4
  integer, parameter :: hruffmethod = 1 ! Method for max hruff
  integer, parameter :: CO2forcingtype=2   ! 1 constant, 2 time-varying,
                                           ! 3 interactive  
  integer, dimension(:), allocatable, save :: cmap
  integer, dimension(5,2), save :: pind  
  real, dimension(:), allocatable, save :: sv,vl1,vl2,vl3

  contains
  ! ****************************************************************************

  ! CABLE-CCAM interface
  subroutine sib4

  use zenith_m
  
  implicit none

  include 'newmpar.h'
  include 'arrays.h'
  include 'carbpools.h'
  include 'const_phys.h' ! grav
  include 'dates.h' ! ktime,kdate,timer,timeg,xg,yg
  include 'extraout.h'
  include 'histave.h'
  include 'latlong.h'  ! rlatt,rlongg
  include 'morepbl.h'
  include 'nsibd.h'
  include 'parm.h'
  include 'permsurf.h'
  include 'pbl.h'
  include 'prec.h'
  include 'screen.h'   ! tscrn etc
  include 'sigs.h'
  include 'soil.h'     ! ... zmin zolnd zolog sice alb
  include 'soilbal.h'
  include 'soilsnow.h' ! 
  include 'vegpar.h' ! 
! met forcing for CBM
  real dirad,dfgdt,degdt,wetfac,degdw,cie
  real factch,qsttg,rho,zo,aft,fh,ri,theta
  real gamm,rg,vmod,dummwk2
  real egg,evapxf,ewww,fgf,fgg,ggflux,rdg,rgg,residf
  real ga,condxpr,fev,fes,ism,fwtop,af,extin,dum3
  common/work2/dirad(ifull),dfgdt(ifull),degdt(ifull)  &
 & ,wetfac(ifull),degdw(ifull),cie(ifull)              &
 & ,factch(ifull),qsttg(ifull),rho(ifull),zo(ifull)    &
 & ,aft(ifull),fh(ifull),ri(ifull),theta(ifull)        &
 & ,gamm(ifull),rg(ifull),vmod(ifull),dummwk2(ifull)
  common/work3/egg(ifull),evapxf(ifull),ewww(ifull),fgf(ifull),  &
 & fgg(ifull),ggflux(ifull),rdg(ifull),rgg(ifull),residf(ifull), &     
 & ga(ifull),condxpr(ifull),fev(ifull),fes(ifull),               &
 & ism(ifull),fwtop(ifull),af(ifull),                            &
 & extin(ifull),dum3(5*ijk-17*ifull)

 ! for calculation of zenith angle
  real fjd, r1, dlt, slag, dhr, coszro2(ifull),taudar2(ifull)
  real bpyear,alp,x
  real tmps(ifull),hruff_grmx(ifull),atmco2(ifull)

  integer jyear,jmonth,jday,jhour,jmin
  integer mstart,ktauplus,k,mins,kstart
  integer nb,monthstart

  integer imonth(12)
  data imonth /31,28,31,30,31,30,31,31,30,31,30,31/
  integer ndoy(12)   ! days from beginning of year (1st Jan is 0)
  data ndoy/ 0,31,59,90,120,151,181,212,243,273,304,334/

  ! Reset averages
  if (ktau==1.or.ktau-1==ntau.or.mod(ktau-1,nperavg)==0) then
    theta_ave=0.
    wb1_ave=0.
    wb2_ave=0.
    wb3_ave=0.
    wb4_ave=0.
    wb5_ave=0.
    wb6_ave=0.
    tgg1_ave=0.
    tgg2_ave=0.
    tgg3_ave=0.
    tgg4_ave=0.
    tgg5_ave=0.
    tgg6_ave=0.
    fpn_ave=0.
    frday_ave=0.
    frp_ave=0.
  end if
    
  ! abort calculation if no land points on this processor  
  if (mp.le.0) return

  ! Set soil moisture to presets when nrungcm.ne.0
  if (ktau==1.and.nrungcm.ne.0) then
    do k=1,ms ! use preset for wb
      ssoil%wb(:,k)=wb(cmap,k)
    end do
    ssoil%wetfac = MAX(0., MIN(1., (ssoil%wb(:,1) - soil%swilt) / (soil%sfc - soil%swilt)))
    ssoil%owetfac = ssoil%wetfac        
  end if

!
! set meteorological forcing
!
  jyear=kdate/10000
  jmonth=(kdate-jyear*10000)/100
  jday=kdate-jyear*10000-jmonth*100
  jhour=ktime/100
  jmin=ktime-jhour*100
  ! mins from start of year
  mstart=1440*(ndoy(jmonth)+jday-1) + 60*jhour + jmin
  ktauplus=0
  do k=1,jmonth-1
   ktauplus = ktauplus + imonth(k)*nperday
  enddo

  ! mtimer contains number of minutes since the start of the run.
  mins = mtimer + mstart
  bpyear = 0.
  fjd = float(mod(mins,525600))/1440.  ! 525600 = 1440*365
  call solargh(fjd,bpyear,r1,dlt,alp,slag)
  dhr = dt/3600.
  call zenith(fjd,r1,dlt,slag,rlatt,rlongg,dhr,ifull,coszro2,taudar2)

  call setco2for(atmco2)

  kstart = 1

  met%doy=fjd
  met%tk=theta(cmap)
  met%ua=vmod(cmap)
  met%ca=1.e-6*atmco2(cmap)
  met%coszen=max(1.e-8,coszro2(cmap)) ! use instantaneous value

  met%qv=qg(cmap,1)        ! specific humidity in kg/kg
  met%pmb=.01*ps(cmap)     ! pressure in mb at ref height
  met%precip=condx(cmap)
  met%hod=(met%doy-int(met%doy))*24. + rlongg(cmap)*180./(15.*pi)
  where (met%hod.gt.24.) met%hod=met%hod-24.
  rough%za_tq=-287.*t(cmap,1)*log(sig(1))/grav   ! reference height
  rough%za_uv=rough%za_tq

  ! swrsave indicates the fraction of net VIS radiation (compared to NIR)
  ! fbeamvis indicates the beam fraction of downwelling direct radiation (compared to diffuse) for VIS
  ! fbeamnir indicates the beam fraction of downwelling direct radiation (compared to diffuse) for NIR
  met%fsd(:,3)=sgsave(cmap)/(1.-swrsave(cmap)*albvisnir(cmap,1) &
              -(1.-swrsave(cmap))*albvisnir(cmap,2)) ! short wave down (positive) W/m^2
  met%fsd(:,1)=swrsave(cmap)*met%fsd(:,3)
  met%fsd(:,2)=(1.-swrsave(cmap))*met%fsd(:,3)
  rad%fbeam(:,1)=fbeamvis(cmap)
  rad%fbeam(:,2)=fbeamnir(cmap)
  rad%fbeam(:,3)=swrsave(cmap)*fbeamvis(cmap)+(1.-swrsave(cmap))*fbeamnir(cmap)
  met%fld=-rgsave(cmap)        ! long wave down (positive) W/m^2

  monthstart=1440*(jday-1) + 60*jhour + jmin ! mins from start of month
  x=min(max(real(mtimer+monthstart)/real(1440.*imonth(jmonth)),0.),1.)
  veg%vlai(:)=vl1+vl2*x+vl3*x*x ! LAI as a function of time
  veg%vlai(:)=max(veg%vlai(:),0.1)
  where (veg%iveg.eq.15.or.veg%iveg.eq.16)
    veg%vlai=0.001
  endwhere

  met%tc=met%tk-273.16
  met%tvair=met%tk
  met%tvrad=met%tk
  met%ua=max(met%ua,umin)
  met%precip_s=0. ! in mm not mm/sec
  where (met%tc<0.) met%precip_s=met%precip

  rough%hruff=max(0.01,veg%hc-1.2*ssoil%snowd/max(ssoil%ssdnn,100.))
  select case(hruffmethod)
    case(0) ! hruff is mixed in a tile (find max hruff for tile)
      hruff_grmx=0.01
      do nb=1,5
        if (pind(nb,1).le.mp) then
          hruff_grmx(cmap(pind(nb,1):pind(nb,2)))=max( &
            hruff_grmx(cmap(pind(nb,1):pind(nb,2))),rough%hruff(pind(nb,1):pind(nb,2)))
        end if
      end do
      rough%hruff_grmx=hruff_grmx(cmap)
    case(1) ! hruff is seperate in a tile (no max hruff for tile)
      rough%hruff_grmx=rough%hruff
    case DEFAULT
      write(6,*) "ERROR: Unsupported hruffmethod ",hruffmethod
      stop
  end select

  !--------------------------------------------------------------
  ! CABLE
  veg%meth = 1
  CALL ruff_resist
  CALL define_air
  CALL init_radiation ! need to be called at every dt
  CALL cab_albedo(ktau, dt, .true.) ! set L_RADUM=.true. as radriv90.f has been called
  CALL define_canopy(ktau,dt,.true.)
  ssoil%owetfac = ssoil%wetfac
  CALL soil_snow(dt, ktau)
  ! need to adjust fe after soilsnow
  canopy%fev = canopy%fevc + canopy%fevw
  ! Calculate total latent heat flux:
  canopy%fe = canopy%fev + canopy%fes
  ! Calculate net radiation absorbed by soil + veg
  canopy%rnet = canopy%fns + canopy%fnv
  ! Calculate radiative/skin temperature:
  rad%trad = ( (1.-rad%transd)*canopy%tv**4 + rad%transd * ssoil%tss**4 )**0.25
  ! Set net ecosystem exchange after adjustments to frs:
  canopy%fnee = canopy%fpn + canopy%frs + canopy%frp
  !--------------------------------------------------------------
      
  ! Unpack tiles into grid point averages.
  ! Note that albsav and albnirsave are the VIS and NIR albedo output from CABLE to
  ! be used by the radiadiation scheme at the next time step.  albvisnir(:,1) and
  ! albvisnir(:,2) are the VIS and NIR albedo used by the radiation scheme for the
  ! current time step.
  tgg(iperm(1:ipland),:)=0.
  wb(iperm(1:ipland),:)=0.
  wbice(iperm(1:ipland),:)=0.
  cplant(iperm(1:ipland),:)=0.
  csoil(iperm(1:ipland),:)=0.
  albsoilsn(iperm(1:ipland),:)=0.
  albsav(iperm(1:ipland))=0.
  albnirsav(iperm(1:ipland))=0.
  albvisdir(iperm(1:ipland))=0.
  albvisdif(iperm(1:ipland))=0.
  albnirdir(iperm(1:ipland))=0.
  albnirdif(iperm(1:ipland))=0.
  runoff(iperm(1:ipland))=0.
  rnof1(iperm(1:ipland))=0.
  rnof2(iperm(1:ipland))=0.
  wbtot(iperm(1:ipland))=0.
  tevap(iperm(1:ipland))=0.
  tprecip(iperm(1:ipland))=0.
  totenbal(iperm(1:ipland))=0.
  trnoff(iperm(1:ipland))=0.
  rtsoil(iperm(1:ipland))=0.
  rnet(iperm(1:ipland))=0.
  fg(iperm(1:ipland))=0.
  eg(iperm(1:ipland))=0.
  ga(iperm(1:ipland))=0.
  epot(iperm(1:ipland))=0.
  tss(iperm(1:ipland))=0.
  tgf(iperm(1:ipland))=0.
  cansto(iperm(1:ipland))=0.
  gflux(iperm(1:ipland))=0.
  sgflux(iperm(1:ipland))=0.
  fnee(iperm(1:ipland))=0.
  fpn(iperm(1:ipland))=0.
  frd(iperm(1:ipland))=0.
  frp(iperm(1:ipland))=0.
  frpw(iperm(1:ipland))=0.
  frpr(iperm(1:ipland))=0.
  frs(iperm(1:ipland))=0.
  sumpn(iperm(1:ipland))=0.
  sumrp(iperm(1:ipland))=0.
  sumrpw(iperm(1:ipland))=0.
  sumrpr(iperm(1:ipland))=0.
  sumrs(iperm(1:ipland))=0.
  sumrd(iperm(1:ipland))=0.
  zo(iperm(1:ipland))=0.
  cduv(iperm(1:ipland))=0.
  ustar(iperm(1:ipland))=0.
  wetfac(iperm(1:ipland))=0.
  tmps=0. ! average isflag
  vlai(iperm(1:ipland))=0.
      
  ! screen and 10m diagnostics - rhscrn calculated in sflux.f
  tscrn(iperm(1:ipland))=0.
  uscrn(iperm(1:ipland))=0.
  qgscrn(iperm(1:ipland))=0.
  u10(iperm(1:ipland))=0.
      
  do nb=1,5
    if (pind(nb,1).le.mp) then
      do k=1,ms
        tgg(cmap(pind(nb,1):pind(nb,2)),k)=tgg(cmap(pind(nb,1):pind(nb,2)),k) &
                                        +sv(pind(nb,1):pind(nb,2))*ssoil%tgg(pind(nb,1):pind(nb,2),k)
        wb(cmap(pind(nb,1):pind(nb,2)),k)=wb(cmap(pind(nb,1):pind(nb,2)),k) &
                                        +sv(pind(nb,1):pind(nb,2))*ssoil%wb(pind(nb,1):pind(nb,2),k)
        wbice(cmap(pind(nb,1):pind(nb,2)),k)=wbice(cmap(pind(nb,1):pind(nb,2)),k) &
                                        +sv(pind(nb,1):pind(nb,2))*ssoil%wbice(pind(nb,1):pind(nb,2),k)
      end do
      do k=1,ncp
        cplant(cmap(pind(nb,1):pind(nb,2)),k)=cplant(cmap(pind(nb,1):pind(nb,2)),k) &
                                        +sv(pind(nb,1):pind(nb,2))*bgc%cplant(pind(nb,1):pind(nb,2),k)
      enddo
      do k=1,ncs
        csoil(cmap(pind(nb,1):pind(nb,2)),k)=csoil(cmap(pind(nb,1):pind(nb,2)),k) &
                                        +sv(pind(nb,1):pind(nb,2))*bgc%csoil(pind(nb,1):pind(nb,2),k)
      enddo
      albsoilsn(cmap(pind(nb,1):pind(nb,2)),1)=albsoilsn(cmap(pind(nb,1):pind(nb,2)),1) &
                                        +sv(pind(nb,1):pind(nb,2))*ssoil%albsoilsn(pind(nb,1):pind(nb,2),1)
      albsoilsn(cmap(pind(nb,1):pind(nb,2)),2)=albsoilsn(cmap(pind(nb,1):pind(nb,2)),2) &
                                        +sv(pind(nb,1):pind(nb,2))*ssoil%albsoilsn(pind(nb,1):pind(nb,2),2)
      albsav(cmap(pind(nb,1):pind(nb,2)))=albsav(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*rad%albedo(pind(nb,1):pind(nb,2),1)
      albnirsav(cmap(pind(nb,1):pind(nb,2)))=albnirsav(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*rad%albedo(pind(nb,1):pind(nb,2),2)
      albvisdir(cmap(pind(nb,1):pind(nb,2)))=albvisdir(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*rad%reffbm(pind(nb,1):pind(nb,2),1)
      albnirdir(cmap(pind(nb,1):pind(nb,2)))=albnirdir(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*rad%reffbm(pind(nb,1):pind(nb,2),2)
      albvisdif(cmap(pind(nb,1):pind(nb,2)))=albvisdif(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*rad%reffdf(pind(nb,1):pind(nb,2),1)
      albnirdif(cmap(pind(nb,1):pind(nb,2)))=albnirdif(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*rad%reffdf(pind(nb,1):pind(nb,2),2)                                                                                        
      runoff(cmap(pind(nb,1):pind(nb,2)))=runoff(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*ssoil%runoff(pind(nb,1):pind(nb,2))
      rnof1(cmap(pind(nb,1):pind(nb,2)))=rnof1(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*ssoil%rnof1(pind(nb,1):pind(nb,2))
      rnof2(cmap(pind(nb,1):pind(nb,2)))=rnof2(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*ssoil%rnof2(pind(nb,1):pind(nb,2))
      wbtot(cmap(pind(nb,1):pind(nb,2)))=wbtot(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*ssoil%wbtot(pind(nb,1):pind(nb,2))
      tevap(cmap(pind(nb,1):pind(nb,2)))=tevap(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*bal%evap_tot(pind(nb,1):pind(nb,2))
      tprecip(cmap(pind(nb,1):pind(nb,2)))=tprecip(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*bal%precip_tot(pind(nb,1):pind(nb,2))
      totenbal(cmap(pind(nb,1):pind(nb,2)))=totenbal(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*bal%ebal_tot(pind(nb,1):pind(nb,2))
      trnoff(cmap(pind(nb,1):pind(nb,2)))=trnoff(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*bal%rnoff_tot(pind(nb,1):pind(nb,2))
      rtsoil(cmap(pind(nb,1):pind(nb,2)))=rtsoil(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))/ssoil%rtsoil(pind(nb,1):pind(nb,2))
      rnet(cmap(pind(nb,1):pind(nb,2)))=rnet(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*canopy%rnet(pind(nb,1):pind(nb,2))
      fg(cmap(pind(nb,1):pind(nb,2)))=fg(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*canopy%fh(pind(nb,1):pind(nb,2))
      eg(cmap(pind(nb,1):pind(nb,2)))=eg(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*canopy%fe(pind(nb,1):pind(nb,2))
      ga(cmap(pind(nb,1):pind(nb,2)))=ga(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*canopy%ga(pind(nb,1):pind(nb,2))
      epot(cmap(pind(nb,1):pind(nb,2)))=epot(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*ssoil%potev(pind(nb,1):pind(nb,2))
      tss(cmap(pind(nb,1):pind(nb,2)))=tss(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*rad%trad(pind(nb,1):pind(nb,2))
      tgf(cmap(pind(nb,1):pind(nb,2)))=tgf(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*canopy%tv(pind(nb,1):pind(nb,2))
      cansto(cmap(pind(nb,1):pind(nb,2)))=cansto(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*canopy%cansto(pind(nb,1):pind(nb,2))
      gflux(cmap(pind(nb,1):pind(nb,2)))=gflux(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*canopy%ghflux(pind(nb,1):pind(nb,2))
      sgflux(cmap(pind(nb,1):pind(nb,2)))=sgflux(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*canopy%sghflux(pind(nb,1):pind(nb,2))
      fnee(cmap(pind(nb,1):pind(nb,2)))=fnee(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*canopy%fnee(pind(nb,1):pind(nb,2))
      fpn(cmap(pind(nb,1):pind(nb,2)))=fpn(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*canopy%fpn(pind(nb,1):pind(nb,2))
      frd(cmap(pind(nb,1):pind(nb,2)))=frd(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*canopy%frday(pind(nb,1):pind(nb,2))
      frp(cmap(pind(nb,1):pind(nb,2)))=frp(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*canopy%frp(pind(nb,1):pind(nb,2))
      frpw(cmap(pind(nb,1):pind(nb,2)))=frpw(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*canopy%frpw(pind(nb,1):pind(nb,2))
      frs(cmap(pind(nb,1):pind(nb,2)))=frs(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*canopy%frs(pind(nb,1):pind(nb,2))
      sumpn(cmap(pind(nb,1):pind(nb,2)))=sumpn(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*sum_flux%sumpn(pind(nb,1):pind(nb,2))
      sumrp(cmap(pind(nb,1):pind(nb,2)))=sumrp(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*sum_flux%sumrp(pind(nb,1):pind(nb,2))
      sumrpw(cmap(pind(nb,1):pind(nb,2)))=sumrpw(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*sum_flux%sumrpw(pind(nb,1):pind(nb,2))
      sumrpr(cmap(pind(nb,1):pind(nb,2)))=sumrpr(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*sum_flux%sumrpr(pind(nb,1):pind(nb,2))
      sumrs(cmap(pind(nb,1):pind(nb,2)))=sumrs(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*sum_flux%sumrs(pind(nb,1):pind(nb,2))
      sumrd(cmap(pind(nb,1):pind(nb,2)))=sumrd(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*sum_flux%sumrd(pind(nb,1):pind(nb,2))
      zo(cmap(pind(nb,1):pind(nb,2)))=zo(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))/log(zmin/max(rough%z0m(pind(nb,1):pind(nb,2)),zobgin))**2
      cduv(cmap(pind(nb,1):pind(nb,2)))=cduv(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*canopy%cduv(pind(nb,1):pind(nb,2))
      ustar(cmap(pind(nb,1):pind(nb,2)))=ustar(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*canopy%us(pind(nb,1):pind(nb,2))
      wetfac(cmap(pind(nb,1):pind(nb,2)))=wetfac(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*ssoil%wetfac(pind(nb,1):pind(nb,2))
      tmps(cmap(pind(nb,1):pind(nb,2)))=tmps(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*real(ssoil%isflag(pind(nb,1):pind(nb,2)))
      vlai(cmap(pind(nb,1):pind(nb,2)))=vlai(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*veg%vlai(pind(nb,1):pind(nb,2))

      tscrn(cmap(pind(nb,1):pind(nb,2)))=tscrn(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*canopy%tscrn(pind(nb,1):pind(nb,2))
      uscrn(cmap(pind(nb,1):pind(nb,2)))=uscrn(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*canopy%uscrn(pind(nb,1):pind(nb,2))
      qgscrn(cmap(pind(nb,1):pind(nb,2)))=qgscrn(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*canopy%qscrn(pind(nb,1):pind(nb,2))
      u10(cmap(pind(nb,1):pind(nb,2)))=u10(cmap(pind(nb,1):pind(nb,2))) &
                                        +sv(pind(nb,1):pind(nb,2))*canopy%ua_10m(pind(nb,1):pind(nb,2))
    end if
  end do
  where (land)
    zo=max(zmin*exp(-sqrt(1./zo)),zobgin)
    rtsoil=1./rtsoil
    cduv=cduv*vmod ! cduv is Cd * vmod in CCAM
    tscrn=tscrn+273.16
  end where
      
  ! The following lines unpack snow.  This is more complicated as we need to decide
  ! how to unpack tiles with 1 layer or 3 layers of snow in the same grid point.
  ! Here we estimate whether the majority of snow points is 1 layer or 3 layers and then
  ! convert each snow tile to that number of layers.  Note these calculations are purely
  ! diagnoistic.  They are not fed back into the CCAM simulation.
  tggsn(iperm(1:ipland),:)=0.
  smass(iperm(1:ipland),:)=0.
  ssdn(iperm(1:ipland),:)=0.
  ssdnn(iperm(1:ipland))=0.
  snowd(iperm(1:ipland))=0.
  snage(iperm(1:ipland))=0.
  where (land.and.tmps.ge.0.5) ! tmps is average isflag
    isflag=1
  elsewhere
    isflag=0
  endwhere
  do nb=1,5 ! update snow (diagnostic only)
    if (pind(nb,1).le.mp) then      
      do k=1,3
        where (ssoil%isflag(pind(nb,1):pind(nb,2)).lt.isflag(cmap(pind(nb,1):pind(nb,2))).and.k.eq.1)          ! pack 1-layer into 3-layer
          tggsn(cmap(pind(nb,1):pind(nb,2)),k)=tggsn(cmap(pind(nb,1):pind(nb,2)),k) &                          ! pack 1-layer into 3-layer
                                           +sv(pind(nb,1):pind(nb,2))*ssoil%tgg(pind(nb,1):pind(nb,2),1)       ! pack 1-layer into 3-layer
          smass(cmap(pind(nb,1):pind(nb,2)),k)=smass(cmap(pind(nb,1):pind(nb,2)),k) &                          ! pack 1-layer into 3-layer
                                           +sv(pind(nb,1):pind(nb,2))*0.05*ssoil%ssdn(pind(nb,1):pind(nb,2),1) ! pack 1-layer into 3-layer
          ssdn(cmap(pind(nb,1):pind(nb,2)),k)=ssdn(cmap(pind(nb,1):pind(nb,2)),k) &                            ! pack 1-layer into 3-layer
                                           +sv(pind(nb,1):pind(nb,2))*ssoil%ssdn(pind(nb,1):pind(nb,2),1)      ! pack 1-layer into 3-layer
        elsewhere (ssoil%isflag(pind(nb,1):pind(nb,2)).lt.isflag(cmap(pind(nb,1):pind(nb,2))).and.k.eq.2)      ! pack 1-layer into 3-layer
          tggsn(cmap(pind(nb,1):pind(nb,2)),k)=tggsn(cmap(pind(nb,1):pind(nb,2)),k) &                          ! pack 1-layer into 3-layer
                                           +sv(pind(nb,1):pind(nb,2))*ssoil%tgg(pind(nb,1):pind(nb,2),1)       ! pack 1-layer into 3-layer
          smass(cmap(pind(nb,1):pind(nb,2)),k)=smass(cmap(pind(nb,1):pind(nb,2)),k) &                          ! pack 1-layer into 3-layer
                                           +sv(pind(nb,1):pind(nb,2))*(ssoil%snowd(pind(nb,1):pind(nb,2)) &    ! pack 1-layer into 3-layer
                                           -0.05*ssoil%ssdn(pind(nb,1):pind(nb,2),1))*0.4                      ! pack 1-layer into 3-layer
          ssdn(cmap(pind(nb,1):pind(nb,2)),k)=ssdn(cmap(pind(nb,1):pind(nb,2)),k) &                            ! pack 1-layer into 3-layer
                                           +sv(pind(nb,1):pind(nb,2))*ssoil%ssdn(pind(nb,1):pind(nb,2),1)      ! pack 1-layer into 3-layer
        elsewhere (ssoil%isflag(pind(nb,1):pind(nb,2)).lt.isflag(cmap(pind(nb,1):pind(nb,2))).and.k.eq.3)      ! pack 1-layer into 3-layer
          tggsn(cmap(pind(nb,1):pind(nb,2)),k)=tggsn(cmap(pind(nb,1):pind(nb,2)),k) &                          ! pack 1-layer into 3-layer
                                           +sv(pind(nb,1):pind(nb,2))*ssoil%tgg(pind(nb,1):pind(nb,2),1)       ! pack 1-layer into 3-layer
          smass(cmap(pind(nb,1):pind(nb,2)),k)=smass(cmap(pind(nb,1):pind(nb,2)),k) &                          ! pack 1-layer into 3-layer
                                           +sv(pind(nb,1):pind(nb,2))*(ssoil%snowd(pind(nb,1):pind(nb,2)) &    ! pack 1-layer into 3-layer
                                           -0.05*ssoil%ssdn(pind(nb,1):pind(nb,2),1))*0.6                      ! pack 1-layer into 3-layer
          ssdn(cmap(pind(nb,1):pind(nb,2)),k)=ssdn(cmap(pind(nb,1):pind(nb,2)),k) &                            ! pack 1-layer into 3-layer
                                           +sv(pind(nb,1):pind(nb,2))*ssoil%ssdn(pind(nb,1):pind(nb,2),1)      ! pack 1-layer into 3-layer
        elsewhere (ssoil%isflag(pind(nb,1):pind(nb,2)).gt.isflag(cmap(pind(nb,1):pind(nb,2))).and.k.eq.1)      ! pack 3-layer into 1-layer
          tggsn(cmap(pind(nb,1):pind(nb,2)),k)=tggsn(cmap(pind(nb,1):pind(nb,2)),k) &                          ! pack 3-layer into 1-layer
                                           +sv(pind(nb,1):pind(nb,2))*273.16                                   ! pack 3-layer into 1-layer
          smass(cmap(pind(nb,1):pind(nb,2)),k)=smass(cmap(pind(nb,1):pind(nb,2)),k) &                          ! pack 3-layer into 1-layer
                                           +sv(pind(nb,1):pind(nb,2))*ssoil%snowd(pind(nb,1):pind(nb,2))       ! pack 3-layer into 1-layer
          ssdn(cmap(pind(nb,1):pind(nb,2)),k)=ssdn(cmap(pind(nb,1):pind(nb,2)),k) &                            ! pack 3-layer into 1-layer
                                           +sv(pind(nb,1):pind(nb,2))*ssoil%ssdnn(pind(nb,1):pind(nb,2))       ! pack 3-layer into 1-layer
        elsewhere (ssoil%isflag(pind(nb,1):pind(nb,2)).gt.isflag(cmap(pind(nb,1):pind(nb,2))).and.k.ge.2)      ! pack 3-layer into 1-layer
          tggsn(cmap(pind(nb,1):pind(nb,2)),k)=tggsn(cmap(pind(nb,1):pind(nb,2)),k) &                          ! pack 3-layer into 1-layer
                                           +sv(pind(nb,1):pind(nb,2))*273.16                                   ! pack 3-layer into 1-layer
          ssdn(cmap(pind(nb,1):pind(nb,2)),k)=ssdn(cmap(pind(nb,1):pind(nb,2)),k) &                            ! pack 3-layer into 1-layer
                                           +sv(pind(nb,1):pind(nb,2))*ssoil%ssdn(pind(nb,1):pind(nb,2),k)      ! pack 3-layer into 1-layer
        elsewhere                                                                                              ! no change in layers
          tggsn(cmap(pind(nb,1):pind(nb,2)),k)=tggsn(cmap(pind(nb,1):pind(nb,2)),k) &                          ! no change in layers
                                           +sv(pind(nb,1):pind(nb,2))*ssoil%tggsn(pind(nb,1):pind(nb,2),k)     ! no change in layers
          smass(cmap(pind(nb,1):pind(nb,2)),k)=smass(cmap(pind(nb,1):pind(nb,2)),k) &                          ! no change in layers
                                           +sv(pind(nb,1):pind(nb,2))*ssoil%smass(pind(nb,1):pind(nb,2),k)     ! no change in layers
          ssdn(cmap(pind(nb,1):pind(nb,2)),k)=ssdn(cmap(pind(nb,1):pind(nb,2)),k) &                            ! no change in layers
                                           +sv(pind(nb,1):pind(nb,2))*ssoil%ssdn(pind(nb,1):pind(nb,2),k)      ! no change in layers
        end where
      end do
      ssdnn(cmap(pind(nb,1):pind(nb,2)))=ssdnn(cmap(pind(nb,1):pind(nb,2))) &
                                           +sv(pind(nb,1):pind(nb,2))*ssoil%ssdnn(pind(nb,1):pind(nb,2))
      snage(cmap(pind(nb,1):pind(nb,2)))=snage(cmap(pind(nb,1):pind(nb,2))) &
                                           +sv(pind(nb,1):pind(nb,2))*ssoil%snage(pind(nb,1):pind(nb,2))
      snowd(cmap(pind(nb,1):pind(nb,2)))=snowd(cmap(pind(nb,1):pind(nb,2))) &
                                           +sv(pind(nb,1):pind(nb,2))*ssoil%snowd(pind(nb,1):pind(nb,2))
    end if
  end do

  ! Averages for Yingping's off-line experiments
  theta_ave=theta_ave+theta
  wb1_ave  =wb1_ave  +wb(:,1)
  wb2_ave  =wb2_ave  +wb(:,2)
  wb3_ave  =wb3_ave  +wb(:,3)
  wb4_ave  =wb4_ave  +wb(:,4)
  wb5_ave  =wb5_ave  +wb(:,5)
  wb6_ave  =wb6_ave  +wb(:,6)                              
  tgg1_ave =tgg1_ave +tgg(:,1)
  tgg2_ave =tgg2_ave +tgg(:,2)
  tgg3_ave =tgg3_ave +tgg(:,3)
  tgg4_ave =tgg4_ave +tgg(:,4)
  tgg5_ave =tgg5_ave +tgg(:,5)
  tgg6_ave =tgg6_ave +tgg(:,6)
  fpn_ave  =fpn_ave  +fpn
  frday_ave=frday_ave+frd
  frp_ave  =frp_ave  +frp
      
  if (ktau==ntau.or.mod(ktau,nperavg)==0) then
    theta_ave=theta_ave/min(ntau,nperavg)
    wb1_ave  =wb1_ave  /min(ntau,nperavg)
    wb2_ave  =wb2_ave  /min(ntau,nperavg)
    wb3_ave  =wb3_ave  /min(ntau,nperavg)
    wb4_ave  =wb4_ave  /min(ntau,nperavg)
    wb5_ave  =wb5_ave  /min(ntau,nperavg)
    wb6_ave  =wb6_ave  /min(ntau,nperavg)
    tgg1_ave =tgg1_ave /min(ntau,nperavg)
    tgg2_ave =tgg2_ave /min(ntau,nperavg)
    tgg3_ave =tgg3_ave /min(ntau,nperavg)
    tgg4_ave =tgg4_ave /min(ntau,nperavg)
    tgg5_ave =tgg5_ave /min(ntau,nperavg)
    tgg6_ave =tgg6_ave /min(ntau,nperavg)
    fpn_ave  =fpn_ave  /min(ntau,nperavg)
    frday_ave=frday_ave/min(ntau,nperavg)
    frp_ave  =frp_ave  /min(ntau,nperavg)
  end if
      
  return
  end subroutine sib4

! *************************************************************************************
  subroutine setco2for(atmco2)
! set co2 forcing for cable
! constant: atmospheric co2 = 360 ppm 
! host: atmospheric co2 follows that from CCAM radiation scheme
! interactive: atmospheric co2 taken from tracer (usually cable+fos+ocean)

  implicit none

  include 'newmpar.h'
  include 'tracers.h'

  integer, parameter :: constantCO2 = 1
  integer, parameter :: hostCO2 = 2
  integer, parameter :: interactiveCO2 = 3
  real, dimension(ifull), intent(out) :: atmco2
  real rrco2,ssolar,rrvco2
  common /radisw2/ rrco2, ssolar, rrvco2

  select case (CO2forcingtype)
    case (constantCO2); atmco2 = 360.
    case (hostCO2) 
      atmco2 = rrvco2 * 1.E6
    case (interactiveCO2)
      !write(6,*) 'need to replace with tracer sum'
      atmco2 = tr(1:ifull,1,1)
  end select

  return
  end subroutine setco2for

! *************************************************************************************
  subroutine loadcbmparm(fveg,fvegprev,fvegnext)

  use cc_mpi
  
  implicit none
  
  include 'newmpar.h'
  include 'const_phys.h'
  include 'carbpools.h'
  include 'latlong.h'  
  include 'nsibd.h'
  include 'parm.h'
  include 'parmgeom.h'  ! rlong0,rlat0,schmidt
  include 'pbl.h'
  include 'sigs.h'
  include 'soil.h'
  include 'soilsnow.h'
  include 'soilv.h'
  include 'vegpar.h' !   

  integer(i_d), dimension(ifull_g,5) :: ivsg
  integer(i_d), dimension(ifull,5) :: ivs
  integer(i_d) iq,n,k,iad,ipos,isoil
  real(r_1) :: totdepth,ra,rb
  real(r_1), dimension(mxvt,ms) :: froot2
  real(r_1), dimension(ifull_g,5) :: svsg,vling
  real(r_1), dimension(ifull,5) :: svs,vlin,vlinprev,vlinnext
  character(len=*), intent(in) :: fveg,fvegprev,fvegnext
  integer ilx,jlx
  real rlong0x,rlat0x,schmidtx,dsx
  character*47 header

  if (myid == 0) write(6,*) "Setting CABLE defaults (igbp)"
  
  zmin=-rdry*280.*log(sig(1))/grav ! not yet defined in indata.f

  hc=(/ 17.,35.,15.5,20.,19.25,0.6,0.6,7.0426,14.3379,0.567,0.5,0.55,6.017,0.55,0.2,0.2,0.2 /)
  xfang=(/ 0.01,0.1,0.01,0.25,0.125,-0.3,0.01,-0.3,-0.3,-0.3,0.,-0.3,0.,-0.3,0.,0.1,0. /)
  dleaf=(/ 0.055,0.1,0.04,0.15,0.1,0.1,0.1,0.233,0.129,0.3,0.3,0.3,0.242,0.3,0.03,0.03,0.03 /)
  canst1=0.1
  shelrb=2.
  extkn=0.7
  refl(:,1)=(/ 0.062,0.076,0.062,0.092,0.069,0.100,0.100,0.091,0.075,0.107,0.107,0.101,0.097,0.101,0.159,0.159,0.159 /)
  refl(:,2)=(/ 0.302,0.350,0.302,0.380,0.336,0.400,0.400,0.414,0.347,0.469,0.469,0.399,0.396,0.399,0.305,0.305,0.305 /)
  taul(:,1)=(/ 0.050,0.050,0.050,0.050,0.050,0.054,0.054,0.062,0.053,0.070,0.070,0.067,0.062,0.067,0.026,0.026,0.026 /)
  taul(:,2)=(/ 0.100,0.250,0.100,0.250,0.158,0.240,0.240,0.221,0.166,0.250,0.250,0.225,0.232,0.250,0.126,0.126,0.126 /)
  vegcf=(/ 0.91, 1.95, 0.73, 1.50, 1.55, 0.60, 2.05, 2.80, 2.75, 2.75, 0.00, 2.80, 0.00, 2.80, 0.00, 0.40, 0.40 /)
  vcmax=(/ 65.2E-6,65.E-6,70.E-6,85.0E-6,80.E-6,20.E-6,20.E-6,10.E-6,20.E-6,10.E-6,50.E-6,80.E-6,1.E-6,80.E-6, &
           17.E-6,17.E-6,17.E-6 /)
  ejmax=2.*vcmax
  rp20=(/ 3.3039,1.1342,3.2879,1.4733,2.3704,5.,5.,1.05,2.,0.8037,1.,3.,1.,3.,0.1,0.1,0.1 /)
  rpcoef=0.0832
  rs20=(/ 1.,1.,1.,1.,1.,1.,1.,1.,1.,1.,1.,1.,1.,1.,0.,0.,0. /)
  tminvj=(/ -15.,-15.,5.,5.,5.,-15.,-15.,-15.,-15.,-15.,-15.,-15.,-15.,-15.,-15.,-15.,-15. /)
  tmaxvj=(/ -10.,-10.,10.,15.,10.,-10.,-10.,-10.,-10.,-10.,-10.,-10.,-10.,-10.,-10.,-10.,-10. /)
  vbeta=(/ 2.,2.,2.,2.,2.,4.,4.,4.,4.,4.,2.,2.,2.,2.,4.,4.,4. /)
  rootbeta=(/ 0.943,0.962,0.966,0.961,0.966,0.914,0.964,0.972,0.943,0.943,0.961,0.961,0.961,0.961,0.961,0.975,0.975 /)
  tcplant(:,1)=(/ 200.  ,300.  ,200.  ,300.  ,200.  ,150. ,150. ,250. ,250. ,250. ,250.,150.,0.1,150.,0.,1.,0. /)
  tcplant(:,2)=(/ 10217.,16833.,5967. ,12000.,10217.,5000.,5000.,5247.,5247.,0.   ,0.  ,0.  ,0. ,0.  ,0.,0.,0. /)
  tcplant(:,3)=(/ 876.  ,1443. ,511.  ,1029. ,876.  ,500. ,500. ,1124.,1124.,500. ,500.,607.,0.1,607.,0.,1.,0. /)
  tcsoil(:,1)=(/ 184.   ,303.  ,107.  ,216.  ,184.  ,100. ,100. ,275. ,275. ,275. ,275.,149.,0.1,149.,0.,1.,0. /)
  tcsoil(:,2)=(/ 367.   ,606.  ,214.  ,432.  ,367.  ,250. ,250. ,314. ,314. ,314. ,314.,300.,0.1,300.,0.,1.,0. /)
  ratecp(1)=1.
  ratecp(2)=0.03
  ratecp(3)=0.14
  ratecs(1)=2.
  ratecs(2)=0.5
  
  if (nrungcm.ne.0) then
    if (myid==0) write(6,*) "Use wb preset for CABLE"
    wb=20.5 ! dummy for now
  end if

  if (any(wb(:,:).gt.10.)) then
    if (myid==0) write(6,*) "Unpacking wetfrac to wb"
    wb(:,:)=wb(:,:)-20.
    do iq=1,ifull
      isoil=isoilm(iq)
      wb(iq,:)=(1.-wb(iq,:))*swilt(isoil)+wb(iq,:)*sfc(isoil)
    end do
  end if


  if (cbm_ms.ne.ms) then
    write(6,*) "ERROR: CABLE and CCAM soil levels do not match"
    stop
  end if

  if (myid==0) then
    write(6,*) "Reading land-use data for CABLE"
    if (fvegprev.ne.' '.and.fvegnext.ne.' ') then
      open(87,file=fvegprev,status='old')
      read(87,*) ilx,jlx,rlong0x,rlat0x,schmidtx,dsx,header
      if(ilx.ne.il_g.or.jlx.ne.jl_g.or.rlong0x.ne.rlong0.or.rlat0x.ne.rlat0.or.schmidtx.ne.schmidt) stop 'wrong data file supplied'
      do iq=1,ifull_g
        read(87,*) iad,ra,rb,ivsg(iq,1),svsg(iq,1),vling(iq,1),ivsg(iq,2),svsg(iq,2),vling(iq,2),ivsg(iq,3),svsg(iq,3),vling(iq,3), &
                   ivsg(iq,4),svsg(iq,4),vling(iq,4),ivsg(iq,5),svsg(iq,5),vling(iq,5)
      end do
      close(87)
      do n=1,5
        call ccmpi_distribute(vlinprev(:,n),vling(:,n))
      end do
      open(87,file=fvegnext,status='old')
      read(87,*) ilx,jlx,rlong0x,rlat0x,schmidtx,dsx,header
      if(ilx.ne.il_g.or.jlx.ne.jl_g.or.rlong0x.ne.rlong0.or.rlat0x.ne.rlat0.or.schmidtx.ne.schmidt) stop 'wrong data file supplied'
      do iq=1,ifull_g
        read(87,*) iad,ra,rb,ivsg(iq,1),svsg(iq,1),vling(iq,1),ivsg(iq,2),svsg(iq,2),vling(iq,2),ivsg(iq,3),svsg(iq,3),vling(iq,3), &
                   ivsg(iq,4),svsg(iq,4),vling(iq,4),ivsg(iq,5),svsg(iq,5),vling(iq,5)
      end do
      close(87)
      do n=1,5
        call ccmpi_distribute(vlinnext(:,n),vling(:,n))
      end do      
    else
      vlinprev=-1.
      vlinnext=-1.    
    end if
    open(87,file=fveg,status='old')
    read(87,*) ilx,jlx,rlong0x,rlat0x,schmidtx,dsx,header
    if(ilx.ne.il_g.or.jlx.ne.jl_g.or.rlong0x.ne.rlong0.or.rlat0x.ne.rlat0.or.schmidtx.ne.schmidt) stop 'wrong data file supplied'
    do iq=1,ifull_g
      read(87,*) iad,ra,rb,ivsg(iq,1),svsg(iq,1),vling(iq,1),ivsg(iq,2),svsg(iq,2),vling(iq,2),ivsg(iq,3),svsg(iq,3),vling(iq,3), &
                 ivsg(iq,4),svsg(iq,4),vling(iq,4),ivsg(iq,5),svsg(iq,5),vling(iq,5)
    end do
    close(87)
    do n=1,5
      call ccmpi_distribute(ivs(:,n),ivsg(:,n))
      call ccmpi_distribute(svs(:,n),svsg(:,n))
      call ccmpi_distribute(vlin(:,n),vling(:,n))
    end do
  else
    if (fvegprev.ne.' '.and.fvegnext.ne.' ') then
      do n=1,5
        call ccmpi_distribute(vlinprev(:,n))
      end do
      do n=1,5
        call ccmpi_distribute(vlinnext(:,n))
      end do
    else
      vlinprev=-1.
      vlinnext=-1.
    end if    
    do n=1,5
      call ccmpi_distribute(ivs(:,n))
      call ccmpi_distribute(svs(:,n))
      call ccmpi_distribute(vlin(:,n))
    end do
  end if
  do n=1,5
    svs(:,n)=svs(:,n)/sum(svs,2)
  end do

  mp=0
  do iq=1,ifull
    if (land(iq)) then
      mp=mp+count(svs(iq,:).gt.0.)
    end if
  end do

  ! default values (i.e., no land)  
  vlai=0.
  zolnd=zobgin
  ivegt=0
  sigmf=0.
  albsoilsn=0.08  
  albsoil=0.08
  albvisdir=0.08
  albvisdif=0.08
  albnirdir=0.08
  albnirdif=0.08
  gflux=0. ! MJT suggestion
  sgflux=0. ! MJT suggestion
  sumpn = 0.
  sumrp = 0.
  sumrs = 0.
  sumrd = 0.
  pind=ifull+1
  
  if (mp.gt.0) then
  
    allocate(sv(mp))
    allocate(vl1(mp),vl2(mp),vl3(mp))
    allocate(cmap(mp))
    call alloc_cbm_var(air, mp)
    call alloc_cbm_var(bgc, mp)
    call alloc_cbm_var(canopy, mp)
    call alloc_cbm_var(met, mp)
    call alloc_cbm_var(bal, mp)
    call alloc_cbm_var(rad, mp)
    call alloc_cbm_var(rough, mp)
    call alloc_cbm_var(soil, mp)
    call alloc_cbm_var(ssoil, mp)
    call alloc_cbm_var(sum_flux, mp)
    call alloc_cbm_var(veg, mp)

    ! soil parameters
    soil%zse = (/.022, .058, .154, .409, 1.085, 2.872/) ! soil layer thickness
    soil%zshh(1) = 0.5 * soil%zse(1)
    soil%zshh(ms+1) = 0.5 * soil%zse(ms)
    soil%zshh(2:ms) = 0.5 * (soil%zse(1:ms-1) + soil%zse(2:ms))
  
    ! preferred option
    ! froot is now calculated from soil depth and the new parameter rootbeta 
    ! according to Jackson et al. 1996, Oceologica, 108:389-411
    totdepth = 0.0
    do k=1,ms
      totdepth = totdepth + soil%zse(k)*100.0
      froot2(:,k) = min(1.0,1.0-rootbeta(:)**totdepth)
    enddo
    do k = ms, 2, -1
      froot2(:,k) = froot2(:,k) - froot2(:,k-1)
    enddo
  
    sv=0.
    vl1=0.
    vl2=0.
    vl3=0.
  
    ipos=0
    do n=1,5
      call getc4(ifull,ivs(:,n),rlatt(:)*180./pi,c4frac(:))
      pind(n,1)=ipos+1
      do iq=1,ifull
        if (land(iq).and.(svs(iq,n).gt.0.)) then
          ipos=ipos+1
          if (ivs(iq,n).lt.1) then
            write(6,*) "ERROR: Land-type/lsmask mismatch at iq=",iq
            stop
          end if
          cmap(ipos)=iq
          sv(ipos)=svs(iq,n)
          veg%iveg(ipos)=ivs(iq,n)
          soil%isoilm(ipos)=isoilm(iq)
          veg%frac4(ipos)=c4frac(iq)
          if (fvegprev.ne.' '.and.fvegnext.ne.' ') then
            vlin(iq,n)=vlin(iq,n)+vlinprev(iq,n)
            vlinnext(iq,n)=vlinnext(iq,n)+vlin(iq,n)
            vl1(ipos)=0.5*vlin(iq,n)
            vl2(ipos)=4.*vlin(iq,n)-5.*vlinprev(iq,n)-vlinnext(iq,n)
            vl3(ipos)=1.5*(vlinnext(iq,n)+3.*vlinprev(iq,n)-3.*vlin(iq,n))
          else
            vl1(ipos)=vlin(iq,n)
            vl2(ipos)=0.
            vl3(ipos)=0.
          end if
          if (veg%iveg(ipos).eq.15.or.veg%iveg(ipos).eq.16) then
            vl1(ipos)=0.001
            vl2(ipos)=0.
            vl3(ipos)=0.
          end if
          veg%vlai(ipos)=vl1(ipos)
        end if
      end do
      pind(n,2)=ipos
    end do
  
    if (ipos.ne.mp) then
      write(6,*) "ERROR: Internal memory allocation error for CABLE set-up"
      stop
    end if

    do n=1,5
      if (pind(n,1).le.mp) then
        vlai(cmap(pind(n,1):pind(n,2)))=vlai(cmap(pind(n,1):pind(n,2))) &
                                        +vl1(pind(n,1):pind(n,2))*sv(pind(n,1):pind(n,2))
      end if
    end do
  
    ! aggregate zom
    do n=1,5
      where (land)
        zolnd=zolnd+svs(:,n)/log(zmin/(0.1*hc(ivs(:,n))))**2
      end where
    end do
    where (land)
      zolnd=max(zmin*exp(-sqrt(1./zolnd)),zobgin)
    end where
  
    ! use dominant veg type
    ivegt=ivs(:,1)
    veg%hc        = hc(veg%iveg)
    veg%canst1    = canst1(veg%iveg)
    veg%ejmax     = ejmax(veg%iveg)
    veg%tminvj    = tminvj(veg%iveg)
    veg%tmaxvj    = tmaxvj(veg%iveg)
    veg%vbeta     = vbeta(veg%iveg)
    veg%rp20      = rp20(veg%iveg)
    veg%rpcoef    = rpcoef(veg%iveg)
    veg%shelrb    = shelrb(veg%iveg)
    veg%vcmax     = vcmax(veg%iveg)
    veg%xfang     = xfang(veg%iveg)
    veg%dleaf     = dleaf(veg%iveg)
    veg%xalbnir   = 1.
    veg%taul(:,1) = taul(veg%iveg,1)
    veg%taul(:,2) = taul(veg%iveg,2)  
    veg%refl(:,1) = refl(veg%iveg,1)
    veg%refl(:,2) = refl(veg%iveg,2)  
    rad%extkn     = extkn(veg%iveg)
    soil%rs20     = rs20(veg%iveg)
    veg%vegcf     = vegcf(veg%iveg)
    do k=1,ms
      veg%froot(:,k)=froot2(veg%iveg,k)
    end do
  
    if (all(cplant.eq.0.)) then
      if (myid == 0) write(6,*) "Using default carbpools"
      do k=1,ncp
        where (land)
          cplant(:,ncp)=tcplant(ivegt,ncp)
        end where
      end do
      do k=1,ncs
        where (land)        
          csoil(:,ncs)=tcsoil(ivegt,ncs)
        end where
      end do
    else
      if (myid == 0) write(6,*) "Loading carbpools from ifile"
    end if
  
    soil%bch     = bch(soil%isoilm)
    soil%css     = css(soil%isoilm)
    soil%rhosoil = rhos(soil%isoilm)
    soil%cnsd    = cnsd(soil%isoilm)
    soil%hyds    = hyds(soil%isoilm)
    soil%sucs    = sucs(soil%isoilm)
    soil%hsbh    = hsbh(soil%isoilm)
    soil%sfc     = sfc(soil%isoilm)
    soil%ssat    = ssat(soil%isoilm)
    soil%swilt   = swilt(soil%isoilm)
    soil%ibp2    = ibp2(soil%isoilm)
    soil%i2bp3   = i2bp3(soil%isoilm)
    soil%pwb_min =  (soil%swilt / soil%ssat )**soil%ibp2
 
    bgc%ratecp(:) = ratecp(:)
    bgc%ratecs(:) = ratecs(:)
  
    where (land)
      sigmf=(1.-exp(-extkn(ivegt(:))*vlai(:)))
    end where

    ! store bare soil albedo and define snow free albedo
    where (land)
      albsoil(:)=0.5*sum(albvisnir,2)
    end where
    where ((albsoil.le.0.14).and.land)
      !sfact=0.5 for alb <= 0.14 (see cable_soilsnow.f90)
      albsoilsn(:,1)=(1.00/1.50)*albsoil(:)
      albsoilsn(:,2)=(2.00/1.50)*albsoil(:)
    elsewhere ((albsoil(:).le.0.2).and.land)
      !sfact=0.62 for 0.14 < alb <= 0.20 (see cable_soilsnow.f90)
      albsoilsn(:,1)=(1.24/1.62)*albsoil(:)
      albsoilsn(:,2)=(2.00/1.62)*albsoil(:)
    elsewhere (land)
      !sfact=0.68 for 0.2 < alb (see cable_soilsnow.f90)
      albsoilsn(:,1)=(1.36/1.68)*albsoil(:)
      albsoilsn(:,2)=(2.00/1.68)*albsoil(:)
    end where
    ! MJT suggestion to get an approx inital albedo (before cable is called)
    where (land)
      albvisnir(:,1)=albsoilsn(:,1)*(1.-sigmf)+0.1*sigmf
      albvisnir(:,2)=albsoilsn(:,2)*(1.-sigmf)+0.3*sigmf
    end where
  
    albvisdir=albvisnir(:,1) ! To be updated by CABLE
    albvisdif=albvisnir(:,1) ! To be updated by CABLE
    albnirdir=albvisnir(:,2) ! To be updated by CABLE
    albnirdif=albvisnir(:,2) ! To be updated by CABLE

    soil%albsoil=albsoil(cmap)
    ssoil%albsoilsn(:,1)=albsoilsn(cmap,1) ! overwritten by CABLE
    ssoil%albsoilsn(:,2)=albsoilsn(cmap,2) ! overwritten by CABLE
    ssoil%albsoilsn(:,3)=0.05
  
    rad%albedo_T = soil%albsoil
    rad%trad=tss(cmap)
    rad%latitude=rlatt(cmap)*180./pi
    rad%longitude=rlongg(cmap)*180./pi
  
    canopy%ghflux=0.
    canopy%sghflux=0.  
  
    ! Initialise sum flux variables
    sum_flux%sumpn=0.
    sum_flux%sumrp=0.
    sum_flux%sumrs=0.
    sum_flux%sumrd=0.
    sum_flux%sumrpw=0.
    sum_flux%sumrpr=0.
    sum_flux%dsumpn=0.
    sum_flux%dsumrp=0.
    sum_flux%dsumrs=0.
    sum_flux%dsumrd=0.
  
    bal%evap_tot=0.
    bal%precip_tot=0.
    bal%ebal_tot=0.
    bal%rnoff_tot=0.
  end if

  call loadtile ! load tgg,wb,wbice,snowd,snage,tggsn,smass,ssdn,isflag,rtsoil,cansto,cplant and csoil

  if (mp.gt.0) then
    ssoil%osnowd=ssoil%snowd                                ! overwritten by CABLE
    bal%osnowd0=ssoil%snowd                                 ! overwritten by CABLE
    ssoil%ssdnn=120.                                        ! overwritten by CABLE
    ssoil%sconds(:,1) = MAX(0.2, MIN(2.876e-6 * ssoil%ssdn(:,1) ** 2 + 0.074, 1.0) )
    where (ssoil%isflag.gt.0)
      ssoil%sdepth(:,1)=ssoil%smass(:,1)/ssoil%ssdn(:,1)    ! overwritten by CABLE
    elsewhere
      ssoil%sdepth(:,1)=ssoil%snowd/ssoil%ssdn(:,1)         ! overwritten by CABLE
    end where
    do k=2,3
      where (ssoil%isflag.gt.0)
        ssoil%sdepth(:,k)=ssoil%smass(:,k)/ssoil%ssdn(:,k)  ! overwritten by CABLE
        ssoil%sconds(:,k) = MAX(0.2, MIN(2.876e-6 * ssoil%ssdn(:,k) ** 2 + 0.074, 1.0) )
      elsewhere
        ssoil%sdepth(:,k)=0.                                ! overwritten by CABLE
        ssoil%sconds(:,k)=0.
      end where
    end do  

    ssoil%wetfac = MAX(0., MIN(1., (ssoil%wb(:,1) - soil%swilt) / (soil%sfc - soil%swilt)))
    ssoil%owetfac = ssoil%wetfac
    ssoil%wbtot=0.
    bal%wbtot0 = ssoil%wbtot
  end if

  do k=1,ms
    ssoil%wb(:,k)=max(ssoil%wb(:,k),soil%swilt)
  end do
  
  return
  end subroutine loadcbmparm

! *************************************************************************************
  subroutine getc4(ifull,ivegt,rlatt,c4frac)
  
  implicit none
  
  integer, intent(in) :: ifull
  integer, dimension(ifull), intent(in) :: ivegt
  real, dimension(ifull), intent(in) :: rlatt
  real, dimension(ifull), intent(out) :: c4frac

  where ((ivegt.eq.7).and.(rlatt.ge.-30.).and.(rlatt.le.30.))
    c4frac=0.95
  elsewhere ((ivegt.eq.8).and.(rlatt.ge.-30.).and.(rlatt.le.0.))
    c4frac=0.5
  elsewhere ((ivegt.eq.8).and.(rlatt.ge.0.).and.(rlatt.le.20.))
    c4frac=0.8
  elsewhere ((ivegt.eq.8).and.(rlatt.ge.20.).and.(rlatt.le.30.))
    c4frac=0.5
  elsewhere (ivegt.eq.9)
    c4frac=0.75
  elsewhere ((ivegt.eq.10).and.(rlatt.ge.-30.).and.(rlatt.le.-20.))
    c4frac=0.5
  elsewhere ((ivegt.eq.10).and.(rlatt.ge.-20.).and.(rlatt.le.20.))
    c4frac=0.95
  elsewhere ((ivegt.eq.10).and.(rlatt.ge.20.).and.(rlatt.le.35.))
    c4frac=0.5
  elsewhere ((ivegt.eq.12).and.(rlatt.ge.0.).and.(rlatt.le.40.))
    c4frac=0.3
  elsewhere
    c4frac=0.
  end where
  
  return
  end subroutine getc4

! *************************************************************************************  
  subroutine loadtile

  use cc_mpi, only : myid
  
  implicit none

  include 'newmpar.h'
  include 'darcdf.h'
  include 'parm.h'
  include 'netcdf.inc'
  include 'mpif.h'
  include 'carbpools.h'
  include 'soil.h'
  include 'soilsnow.h'
  include 'vegpar.h'    
  
  integer k,n,ierr,ierr2,idv
  real, dimension(ifull) :: dat
  character*9 vname
  !real sigin  
  !integer ik,jk,kk
  !common/sigin/ik,jk,kk,sigin(40)  ! for vertint, infile ! MJT bug  

  if (io_in.eq.1) then
    if (myid.eq.0) idv = ncvid(ncid,"tgg1_1",ierr)
    call MPI_Bcast(ierr,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr2)    
  else
    ierr=1
  end if
  
  if (ierr.ne.0) then
    if (myid==0) write(6,*) "Use gridbox averaged data to initialise CABLE"
    if (mp.gt.0) then
      do k = 1,ms
        ssoil%tgg(:,k) = tgg(cmap,k)
        ssoil%wb(:,k) = wb(cmap,k)
        ssoil%wbice(:,k) = wbice(cmap,k)
      enddo
      do k = 1,3
        ssoil%tggsn(:,k) = tggsn(cmap,k)
        ssoil%smass(:,k) = smass(cmap,k)
        ssoil%ssdn(:,k) = ssdn(cmap,k)
      enddo      
      ssoil%isflag=isflag(cmap)
      ssoil%snowd=snowd(cmap)
      ssoil%snage=snage(cmap)
      ssoil%rtsoil=100.
      canopy%cansto=0.
      do k=1,ncp
        bgc%cplant(:,k) = cplant(cmap,k)
      enddo
      do k=1,ncs
        bgc%csoil(:,k) = csoil(cmap,k)
      enddo
    end if
  else
    if (myid==0) write(6,*) "Use tiled data to initialise CABLE"
    do n=1,5
      do k=1,ms
        write(vname,'("tgg",I1.1,"_",I1.1)') k,n
        call histrd1(ncid,iarchi-1,ierr,vname,il_g,jl_g,dat,ifull)
        if (pind(n,1).le.mp) ssoil%tgg(pind(n,1):pind(n,2),k)=dat(cmap(pind(n,1):pind(n,2)))
        write(vname,'("wb",I1.1,"_",I1.1)') k,n
        call histrd1(ncid,iarchi-1,ierr,vname,il_g,jl_g,dat,ifull)
        if (pind(n,1).le.mp) ssoil%wb(pind(n,1):pind(n,2),k)=dat(cmap(pind(n,1):pind(n,2)))
        write(vname,'("wbice",I1.1,"_",I1.1)') k,n
        call histrd1(ncid,iarchi-1,ierr,vname,il_g,jl_g,dat,ifull)
        if (pind(n,1).le.mp) ssoil%wbice(pind(n,1):pind(n,2),k)=dat(cmap(pind(n,1):pind(n,2)))
      end do
      do k=1,3
        write(vname,'("tggsn",I1.1,"_",I1.1)') k,n
        call histrd1(ncid,iarchi-1,ierr,vname,il_g,jl_g,dat,ifull)
        if (pind(n,1).le.mp) ssoil%tggsn(pind(n,1):pind(n,2),k)=dat(cmap(pind(n,1):pind(n,2)))
        write(vname,'("smass",I1.1,"_",I1.1)') k,n
        call histrd1(ncid,iarchi-1,ierr,vname,il_g,jl_g,dat,ifull)
        if (pind(n,1).le.mp) ssoil%smass(pind(n,1):pind(n,2),k)=dat(cmap(pind(n,1):pind(n,2)))
        write(vname,'("ssdn",I1.1,"_",I1.1)') k,n
        call histrd1(ncid,iarchi-1,ierr,vname,il_g,jl_g,dat,ifull)
        if (pind(n,1).le.mp) ssoil%ssdn(pind(n,1):pind(n,2),k)=dat(cmap(pind(n,1):pind(n,2)))
      end do
      write(vname,'("sflag_",I1.1)') n
      call histrd1(ncid,iarchi-1,ierr,vname,il_g,jl_g,dat,ifull)
      if (pind(n,1).le.mp) ssoil%isflag(pind(n,1):pind(n,2))=nint(dat(cmap(pind(n,1):pind(n,2))))
      write(vname,'("snd_",I1.1)') n
      call histrd1(ncid,iarchi-1,ierr,vname,il_g,jl_g,dat,ifull)
      if (pind(n,1).le.mp) ssoil%snowd(pind(n,1):pind(n,2))=dat(cmap(pind(n,1):pind(n,2)))
      write(vname,'("snage_",I1.1)') n
      call histrd1(ncid,iarchi-1,ierr,vname,il_g,jl_g,dat,ifull)
      if (pind(n,1).le.mp) ssoil%snage(pind(n,1):pind(n,2))=dat(cmap(pind(n,1):pind(n,2)))
      write(vname,'("rtsoil_",I1.1)') n
      call histrd1(ncid,iarchi-1,ierr,vname,il_g,jl_g,dat,ifull)
      if (pind(n,1).le.mp) ssoil%rtsoil(pind(n,1):pind(n,2))=dat(cmap(pind(n,1):pind(n,2)))
      write(vname,'("cansto_",I1.1)') n
      call histrd1(ncid,iarchi-1,ierr,vname,il_g,jl_g,dat,ifull)
      if (pind(n,1).le.mp) canopy%cansto(pind(n,1):pind(n,2))=dat(cmap(pind(n,1):pind(n,2)))
      do k=1,ncp
        write(vname,'("cplant",I1.1,"_",I1.1)') k,n
        call histrd1(ncid,iarchi-1,ierr,vname,il_g,jl_g,dat,ifull)
        if (pind(n,1).le.mp) bgc%cplant(pind(n,1):pind(n,2),k) = dat(cmap(pind(n,1):pind(n,2))) 
      enddo
      do k=1,ncs
        write(vname,'("csoil",I1.1,"_",I1.1)') k,n
        call histrd1(ncid,iarchi-1,ierr,vname,il_g,jl_g,dat,ifull)
        if (pind(n,1).le.mp) bgc%csoil(pind(n,1):pind(n,2),k) = dat(cmap(pind(n,1):pind(n,2)))
      enddo
    end do
    ! albvisdir, albvisdif, albnirdir, albnirdif are used when nrad=5
    vname='albvisdir'
    call histrd1(ncid,iarchi-1,ierr,vname,il_g,jl_g,albvisdir,ifull)
    vname='albvisdif'
    call histrd1(ncid,iarchi-1,ierr,vname,il_g,jl_g,albvisdif,ifull)
    vname='albnirdir'
    call histrd1(ncid,iarchi-1,ierr,vname,il_g,jl_g,albnirdir,ifull)
    vname='albnirdif'
    call histrd1(ncid,iarchi-1,ierr,vname,il_g,jl_g,albnirdif,ifull)
    ! albvis and albnir are used when nrad=4
    vname='albvis'
    call histrd1(ncid,iarchi-1,ierr,vname,il_g,jl_g,albvisnir(:,1),ifull)
    vname='albnir'
    call histrd1(ncid,iarchi-1,ierr,vname,il_g,jl_g,albvisnir(:,2),ifull)        
  end if
  
  ssoil%wb=max(ssoil%wb,0.)
  ssoil%wbice=max(ssoil%wbice,0.)
  ssoil%smass=max(ssoil%smass,0.)
  ssoil%rtsoil=max(ssoil%rtsoil,0.)
  canopy%cansto=max(canopy%cansto,0.)
  bgc%cplant=max(bgc%cplant,0.)
  bgc%csoil=max(bgc%csoil,0.)
  
  return
  end subroutine loadtile

 ! *************************************************************************************
  subroutine savetile(idnc,local,idim,iarch)

  use cc_mpi, only : myid
  
  implicit none

  include 'newmpar.h'
  include 'carbpools.h'
  include 'soil.h'
  include 'soilsnow.h'
  include 'vegpar.h'
  
  integer, intent(in) :: idnc,iarch
  integer k,n,ierr
  integer, dimension(3), intent(in) :: idim  
  real, dimension(ifull) :: dat
  character*9 vname
  character*40 lname
  logical, intent(in) :: local
  !real sigin  
  !integer ik,jk,kk
  !common/sigin/ik,jk,kk,sigin(40)  ! for vertint, infile ! MJT bug    
  
  if (myid.eq.0) then
    write(6,*) "Storing CABLE tile data"
    call ncredf(idnc,ierr)
    do n=1,5
      do k=1,ms
        write(lname,'("Soil temperature lev ",I1.1," tile ",I1.1)') k,n
        write(vname,'("tgg",I1.1,"_",I1.1)') k,n
        call attrib(idnc,idim,3,vname,lname,'K',100.,400.,0)
        write(lname,'("Soil moisture lev ",I1.1," tile ",I1.1)') k,n
        write(vname,'("wb",I1.1,"_",I1.1)') k,n 
        call attrib(idnc,idim,3,vname,lname,'m3/m3',0.,1.3,0)
        write(lname,'("Soil ice lev ",I1.1," tile ",I1.1)') k,n
        write(vname,'("wbice",I1.1,"_",I1.1)') k,n 
        call attrib(idnc,idim,3,vname,lname,'m3/m3',0.,1.3,0)
      end do
      do k=1,3
        write(lname,'("Snow temperature lev ",I1.1," tile ",I1.1)') k,n
        write(vname,'("tggsn",I1.1,"_",I1.1)') k,n
        call attrib(idnc,idim,3,vname,lname,'K',100.,400.,0)
        write(lname,'("Snow mass lev ",I1.1," tile ",I1.1)') k,n
        write(vname,'("smass",I1.1,"_",I1.1)') k,n 
        call attrib(idnc,idim,3,vname,lname,'K',0.,650.,0)
        write(lname,'("Snow density lev ",I1.1," tile ",I1.1)') k,n
        write(vname,'("ssdn",I1.1,"_",I1.1)') k,n 
        call attrib(idnc,idim,3,vname,lname,'kg/m3',0.,400.,0)
      end do
      write(lname,'("Snow flag tile ",I1.1)') n
      write(vname,'("sflag_",I1.1)') n
      call attrib(idnc,idim,3,vname,lname,'mm',0.,6.5,0)
      write(lname,'("Snow depth tile ",I1.1)') n
      write(vname,'("snd_",I1.1)') n
      call attrl (idnc,idim,3,vname,lname,'mm',0.,5000.,0)  ! long
      write(lname,'("Snow age tile ",I1.1)') n
      write(vname,'("snage_",I1.1)') n
      call attrib(idnc,idim,3,vname,lname,'none',0.,20.,0)
      write(lname,'("Soil turbulent resistance tile ",I1.1)') n
      write(vname,'("rtsoil_",I1.1)') n
      call attrib(idnc,idim,3,vname,lname,'none',0.,1.3e5,0)
      write(lname,'("cansto tile ",I1.1)') n
      write(vname,'("cansto_",I1.1)') n
      call attrib(idnc,idim,3,vname,lname,'none',0.,13.,0)
      write(lname,'("Carbon leaf pool tile ",I1.1)') n
      write(vname,'("cplant1_",I1.1)') n    
      call attrib(idnc,idim,3,vname,lname,'none',0.,65000.,0)
      write(lname,'("Carbon wood pool tile ",I1.1)') n
      write(vname,'("cplant2_",I1.1)') n
      call attrib(idnc,idim,3,vname,lname,'none',0.,65000.,0)
      write(lname,'("Carbon root pool tile ",I1.1)') n
      write(vname,'("cplant3_",I1.1)') n
      call attrib(idnc,idim,3,vname,lname,'none',0.,65000.,0)
      write(lname,'("Carbon soil fast pool tile ",I1.1)') n
      write(vname,'("csoil1_",I1.1)') n
      call attrib(idnc,idim,3,vname,lname,'none',0.,65000.,0)
      write(lname,'("Carbon soil slow pool tile ",I1.1)') n
      write(vname,'("csoil2_",I1.1)') n
      call attrib(idnc,idim,3,vname,lname,'none',0.,65000.,0)
    end do
    lname='DIR VIS albedo'
    vname='albvisdir'
    call attrib(idnc,idim,3,vname,lname,'none',0.,1.,0)
    lname='DIF VIS albedo'
    vname='albvisdif'
    call attrib(idnc,idim,3,vname,lname,'none',0.,1.,0)
    lname='DIR NIR albedo'
    vname='albnirdir'
    call attrib(idnc,idim,3,vname,lname,'none',0.,1.,0)
    lname='DIF NIR albedo'
    vname='albnirdif'
    call attrib(idnc,idim,3,vname,lname,'none',0.,1.,0)
    lname='VIS albedo'
    vname='albvis'
    call attrib(idnc,idim,3,vname,lname,'none',0.,1.,0)
    lname='NIR albedo'
    vname='albnir'
    call attrib(idnc,idim,3,vname,lname,'none',0.,1.,0)
    call ncendf(idnc,ierr)
  end if
  do n=1,5
    do k=1,ms
      dat=tgg(:,k)
      if (pind(n,1).le.mp) then      
        dat(cmap(pind(n,1):pind(n,2)))=ssoil%tgg(pind(n,1):pind(n,2),k)
      end if
      write(vname,'("tgg",I1.1,"_",I1.1)') k,n
      call histwrt3(dat,vname,idnc,iarch,local)
      dat=wb(:,k)
      if (pind(n,1).le.mp) then  
        dat(cmap(pind(n,1):pind(n,2)))=ssoil%wb(pind(n,1):pind(n,2),k)
      end if
      write(vname,'("wb",I1.1,"_",I1.1)') k,n
      call histwrt3(dat,vname,idnc,iarch,local)
      dat=wbice(:,k)
      if (pind(n,1).le.mp) then  
        dat(cmap(pind(n,1):pind(n,2)))=ssoil%wbice(pind(n,1):pind(n,2),k)
      end if
      write(vname,'("wbice",I1.1,"_",I1.1)') k,n
      call histwrt3(dat,vname,idnc,iarch,local)
    end do
    do k=1,3
      dat=tggsn(:,k)
      if (pind(n,1).le.mp) dat(cmap(pind(n,1):pind(n,2)))=ssoil%tggsn(pind(n,1):pind(n,2),k)
      write(vname,'("tggsn",I1.1,"_",I1.1)') k,n
      call histwrt3(dat,vname,idnc,iarch,local)
      dat=smass(:,k)
      if (pind(n,1).le.mp) dat(cmap(pind(n,1):pind(n,2)))=ssoil%smass(pind(n,1):pind(n,2),k)
      write(vname,'("smass",I1.1,"_",I1.1)') k,n
      call histwrt3(dat,vname,idnc,iarch,local)
      dat=ssdn(:,k)
      if (pind(n,1).le.mp) dat(cmap(pind(n,1):pind(n,2)))=ssoil%ssdn(pind(n,1):pind(n,2),k)
      write(vname,'("ssdn",I1.1,"_",I1.1)') k,n
      call histwrt3(dat,vname,idnc,iarch,local)
    end do
    dat=real(isflag)
    if (pind(n,1).le.mp) dat(cmap(pind(n,1):pind(n,2)))=real(ssoil%isflag(pind(n,1):pind(n,2)))
    write(vname,'("sflag_",I1.1)') n
    call histwrt3(dat,vname,idnc,iarch,local)
    dat=snowd
    if (pind(n,1).le.mp) dat(cmap(pind(n,1):pind(n,2)))=ssoil%snowd(pind(n,1):pind(n,2))
    write(vname,'("snd_",I1.1)') n
    call histwrt3(dat,vname,idnc,iarch,local)  ! long write    
    dat=snage
    if (pind(n,1).le.mp) dat(cmap(pind(n,1):pind(n,2)))=ssoil%snage(pind(n,1):pind(n,2))
    write(vname,'("snage_",I1.1)') n
    call histwrt3(dat,vname,idnc,iarch,local)
    dat=rtsoil
    if (pind(n,1).le.mp) dat(cmap(pind(n,1):pind(n,2)))=ssoil%rtsoil(pind(n,1):pind(n,2))
    write(vname,'("rtsoil_",I1.1)') n
    call histwrt3(dat,vname,idnc,iarch,local)   
    dat=cansto
    if (pind(n,1).le.mp) dat(cmap(pind(n,1):pind(n,2)))=canopy%cansto(pind(n,1):pind(n,2))
    write(vname,'("cansto_",I1.1)') n
    call histwrt3(dat,vname,idnc,iarch,local)
    do k=1,ncp
      dat=cplant(:,k)
      if (pind(n,1).le.mp) dat(cmap(pind(n,1):pind(n,2)))=bgc%cplant(pind(n,1):pind(n,2),k)
      write(vname,'("cplant",I1.1,"_",I1.1)') k,n
      call histwrt3(dat,vname,idnc,iarch,local)    
    end do
    do k=1,ncs
      dat=csoil(:,k)
      if (pind(n,1).le.mp) dat(cmap(pind(n,1):pind(n,2)))=bgc%csoil(pind(n,1):pind(n,2),k)
      write(vname,'("csoil",I1.1,"_",I1.1)') k,n
      call histwrt3(dat,vname,idnc,iarch,local)
    end do
  end do
  vname='albvisdir'
  call histwrt3(albvisdir,vname,idnc,iarch,local)
  vname='albvisdif'
  call histwrt3(albvisdif,vname,idnc,iarch,local)
  vname='albnirdir'
  call histwrt3(albnirdir,vname,idnc,iarch,local)
  vname='albnirdif'
  call histwrt3(albnirdif,vname,idnc,iarch,local)
  vname='albvis'
  call histwrt3(albvisnir(:,1),vname,idnc,iarch,local)
  vname='albnir'
  call histwrt3(albvisnir(:,2),vname,idnc,iarch,local)
  
  return
  end subroutine savetile 

end module cable_ccam

