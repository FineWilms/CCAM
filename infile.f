      module infile
      
      ! This module contains routines for reading netcdf files
            
      private
      public histrd1,histrd4s,vertint,datefix
      
      contains

c*************************************************************************
      subroutine histrd1(ncid,iarchi,ier,name,ik,jk,var,ifull)
      use cc_mpi
      implicit none
      integer ncid,iarchi,ier,ik,jk,ifull
      character name*(*)
      real, dimension(:), intent(inout) :: var ! may be dummy argument from myid.ne.0
      if (myid==0) then
        if (size(var).ne.ifull) then
          write(6,*) "ERROR: Incorrect use of dummy var in histrd1"
          stop
        end if
        call hr1a(ncid,iarchi,ier,name,ik,jk,var,ifull)
      else
        call hr4sb(ier,ik,jk,var,ifull)      
      end if
      return
      end subroutine histrd1    

      subroutine hr1a(ncid,iarchi,ier,name,ik,jk,var,ifull)  ! 0808
      use cc_mpi
      implicit none
      include 'parm.h'
      include 'netcdf.inc'
      include 'mpif.h'
      integer ncid, iarchi, ier, ik, jk, nctype, ierb ! MJT CHANGE - bug fix
      integer*2 ivar(ik*jk)
      logical odiag
      parameter(odiag=.false. )
      character name*(*)
      integer start(3),count(3),ifull
      real  var(ifull)
      real globvar(ik*jk), vmax, vmin, addoff, sf  ! 0808
      integer ierr, idv

      start = (/ 1, 1, iarchi /)
      count = (/ ik, jk, 1 /)

c     get variable idv
      idv = ncvid(ncid,name,ier)
      if(ier.ne.0)then
       write(6,*) '***absent field for ncid,name,idv,ier: ',
     &                              ncid,name,idv,ier
      else
       if(odiag)write(6,*)'ncid,name,idv,ier',ncid,name,idv,ier
       if(odiag)write(6,*)'start=',start
       if(odiag)write(6,*)'count=',count
c      read in all data
       ierr=nf_inq_vartype(ncid,idv,nctype)
       addoff=0.
       sf=1.
       select case(nctype)
        case(nf_float)
         call ncvgt(ncid,idv,start,count,globvar,ier)
         if(odiag)write(6,*)'rvar(1)(ik*jk)=',globvar(1),globvar(ik*jk)
        case(nf_short)
         call ncvgt(ncid,idv,start,count,ivar,ier)
         if(odiag)write(6,*)'ivar(1)(ik*jk)=',ivar(1),ivar(ik*jk)
         globvar(:)=real(ivar(:))
        case DEFAULT
         write(6,*) "ERROR: Unknown NetCDF format"
         stop
       end select

c      obtain scaling factors and offsets from attributes
       call ncagt(ncid,idv,'add_offset',addoff,ierb)
       if (ierb.ne.0) addoff=0.        ! MJT CHANGE - bug fix
       if(odiag)write(6,*)'addoff,ier=',addoff,ier
       call ncagt(ncid,idv,'scale_factor',sf,ierb)
       if (ierb.ne.0) sf=1.            ! MJT CHANGE - bug fix
       if(odiag)write(6,*)'sf,ier=',sf,ier

c      unpack data
       globvar = globvar*sf+addoff ! MJT CHANGE
       if(mod(ktau,nmaxpr)==0.or.odiag)then
        vmax = maxval(globvar*sf+addoff) ! MJT CHANGE
        vmin = minval(globvar*sf+addoff) ! MJT CHANGE
        write(6,'("done histrd1 ",a8,i4,i3,3e14.6)')
     &   name,ier,iarchi,vmin,vmax,globvar(id+(jd-1)*ik)
       endif
      endif ! ier

      ! Have to return correct value of ier on all processes because it's 
      ! used for initialisation in calling routine
      call MPI_Bcast(ier,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      if(ifull==ik*jk)then  !  808
       if(ier==0)then
        var(:)=globvar(:) ! MJT bug
       endif
      else
       if(ier==0)then
        call ccmpi_distribute(var,globvar)
       endif
      endif
      return    ! histrd1
      end subroutine hr1a  

      !--------------------------------------------------------------
      ! MJT otf small - this version reads a single kk level of a 3d field
      subroutine histrd4s(ncid,iarchi,ier,name,ik,jk,kk,var,ifull)
      use cc_mpi
      implicit none
      integer ncid,iarchi,ier,ik,jk,kk,ifull
      character name*(*)
      real, dimension(:), intent(inout) :: var ! may be dummy argument from myid.ne.0
      if (myid==0) then
        if (size(var).ne.ifull) then
          write(6,*) "ERROR: Incorrect use of dummy var in histrd4s"
          stop
        end if
        call hr4sa(ncid,iarchi,ier,name,ik,jk,kk,var,ifull)
      else
        call hr4sb(ier,ik,jk,var,ifull)      
      end if
      return
      end subroutine histrd4s      

      subroutine hr4sa(ncid,iarchi,ier,name,ik,jk,kk,var,ifull)
      use cc_mpi
      implicit none
      include 'netcdf.inc'
      include 'parm.h'
      include 'mpif.h'
      integer ncid,iarchi,ier,ik,jk,kk,ifull
      integer idv,ierb,nctype
      integer start(4),count(4)      
      integer*2 ivar(ik*jk)
      character name*(*)
      real vmax, vmin, addoff, sf
      real var(ifull)
      real globvar(ik*jk)
           
      start = (/ 1, 1, kk, iarchi /)
      count = (/   ik,   jk, 1, 1 /)
      idv = ncvid(ncid,name,ier)
      if(ier.ne.0)then
       write(6,*) '***absent hist4 field for ncid,name,idv,ier: ',
     &                                         ncid,name,idv,ier
      else
c      read in all data
       ier=nf_inq_vartype(ncid,idv,nctype)
       select case(nctype)
        case(nf_float)
         call ncvgt(ncid,idv,start,count,globvar,ier)
        case(nf_short)
         call ncvgt(ncid,idv,start,count,ivar,ier)
         globvar(:)=real(ivar(:))
        case DEFAULT
         write(6,*) "ERROR: Unknown NetCDF format"
         stop
       end select

c      obtain scaling factors and offsets from attributes
       call ncagt(ncid,idv,'add_offset',addoff,ierb)
       if (ierb.ne.0) addoff=0.
       call ncagt(ncid,idv,'scale_factor',sf,ierb)
       if (ierb.ne.0) sf=1.
           
c      unpack data
       globvar=globvar*sf + addoff

       if(mod(ktau,nmaxpr)==0)then
        vmax = maxval(globvar)
        vmin = minval(globvar)
        write(6,'("done histrd4s ",a6,i3,i4,i3,3f12.4)') 
     &   name,kk,ier,iarchi,vmin,vmax,globvar(id+(jd-1)*ik)
       endif
      endif ! ier

      ! Have to return correct value of ier on all processes because it's 
      ! used for initialisation in calling routine
      call MPI_Bcast(ier,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierb)
      if(ifull==ik*jk)then  !  808
       if(ier==0)then
        var(:)=globvar(:)
       end if
      else
       if(ier==0)then
        call ccmpi_distribute(var,globvar)
       end if
      endif

      return
      end subroutine hr4sa      
      
      subroutine hr4sb(ier,ik,jk,var,ifull)
      use cc_mpi
      implicit none
      include 'mpif.h'
      integer ier,ik,jk,ifull
      integer ierb
      real, dimension(:), intent(inout) :: var ! may be dummy argument from myid.ne.0
      ! Have to return correct value of ier on all processes because it's 
      ! used for initialisation in calling routine
      call MPI_Bcast(ier,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierb)
      if(ifull.ne.ik*jk)then  !  808
       if(ier==0)then
        if (size(var).ne.ifull) then
          write(6,*) "ERROR: Incorrect use of dummy var in histrd"
          stop
        end if
        call ccmpi_distribute(var)
       endif
      endif
      return
      end subroutine hr4sb     
      !--------------------------------------------------------------   

      ! This version of vertint can interpolate from host models with
      ! a greater number of vertical levels than the nested model.
      subroutine vertint(told,t,n,kk,sigin) ! MJT vertint
!     N.B. this ia called just from indata or nestin      
!     transforms 3d array from dimension kk in vertical to kl   jlm
!     jlm vector special, just with linear new=1 option
      use sigs_m
      include 'newmpar.h'
      include 'parm.h'
      integer, intent(in) :: kk ! MJT vertint
      real, dimension(kk), intent(in) :: sigin ! MJT vertint
      dimension t(ifull,kl)  ! for mpi
      real, dimension(:), allocatable, save :: ka,kb,wta,wtb
      real told(ifull,kk) ! MJT vertint
      save num,klapse
      data num/0/,klapse/0/
      
      if (.not.allocated(ka)) then
        allocate(ka(kl),kb(kl),wta(kl),wtb(kl))
      end if
      
      if (abs(sig(2)-sigin(2))<0.0001.and.kk.eq.kl) then ! MJT vertint
        t=told                                           ! MJT vertint
        return                                           ! MJT vertint
      end if                                             ! MJT vertint
      
      if(num==0)then
        num=1
        do k=1,kl
         if(sig(k)>=sigin(1))then
           ka(k)=2
           kb(k)=1
           wta(k)=0.
           wtb(k)=1.
           klapse=k   ! i.e. T lapse correction for k<=klapse
         elseif(sig(k)<=sigin(kk))then   ! at top
           ka(k)=kk
           kb(k)=kk-1
           wta(k)=1.
           wtb(k)=0.
         else
           kin=2
           do kin=2,kk
            if(sig(k)>sigin(kin)) exit ! MJT
           enddo     ! kin loop
           ka(k)=kin
           kb(k)=kin-1
           wta(k)=(sigin(kin-1)-sig(k))/(sigin(kin-1)-sigin(kin))
           wtb(k)=(sig(k)-sigin(kin)  )/(sigin(kin-1)-sigin(kin))
         endif  !  (sig(k)>=sigin(1)) ... ...
        enddo   !  k loop
        write(6,*) 'in vertint kk,kl ',kk,kl
        write(6,91) (sigin(k),k=1,kk)
91      format('sigin',10f7.4)
        write(6,92) sig
92      format('sig  ',10f7.4)
        write(6,*) 'ka ',ka
        write(6,*) 'kb ',kb
        write(6,93) wta
93      format('wta',10f7.4)
        write(6,94) wtb
94      format('wtb',10f7.4)
      endif     !  (num==0)

      !told(:,:)=t(:,:) ! MJT vertint
      do k=1,kl
       do iq=1,ifull
!        N.B. "a" denotes "above", "b" denotes "below"
         t(iq,k)=wta(k)*told(iq,ka(k))+wtb(k)*told(iq,kb(k))
       enddo   ! iq loop
      enddo    ! k loop
c     print *,'in vertint told',told(idjd,:)
c     print *,'in vertint t',t(idjd,:)

      if(n==1.and.klapse.ne.0)then  ! for T lapse correction
        do k=1,klapse
         do iq=1,ifull
!         assume 6.5 deg/km, with dsig=.1 corresponding to 1 km
           t(iq,k)=t(iq,k)+(sig(k)-sigin(1))*6.5/.1
         enddo   ! iq loop
        enddo    ! k loop
      endif

      if(n==2)then  ! for qg do a -ve fix
        t(:,:)=max(t(:,:),1.e-6)
      endif
      if(n==5)then  ! for qfg, qlg do a -ve fix
        t(:,:)=max(t(:,:),0.)
      endif
      return
      end subroutine vertint

      subroutine datefix(kdate_r,ktime_r,mtimer_r)
      include 'newmpar.h'
      include 'parm.h'
      common/leap_yr/leap  ! 1 to allow leap years
      integer mdays(12)
      data mdays/31,28,31,30,31,30,31,31,30,31,30,31/
      data minsday/1440/,minsyr/525600/
      if(kdate_r>=00600000.and.kdate_r<=00991231)then   ! old 1960-1999
        kdate_r=kdate_r+19000000
        write(6,*) 'For Y2K kdate_r altered to: ',kdate_r
      endif
      iyr=kdate_r/10000
      imo=(kdate_r-10000*iyr)/100
      iday=kdate_r-10000*iyr-100*imo
      ihr=ktime_r/100
      imins=ktime_r-100*ihr
      write(6,*) 'entering datefix iyr,imo,iday,ihr,imins,mtimer_r: ',
     .                          iyr,imo,iday,ihr,imins,mtimer_r
   !   do while (mtimer_r>minsyr) ! MJT bug fix
   !    iyr=iyr+1
   !    mtimer_r=mtimer_r-minsyr
   !   enddo
   !   if(diag)print *,'a datefix iyr,imo,iday,ihr,imins,mtimer_r: ',
   !  .                   iyr,imo,iday,ihr,imins,mtimer_r

      mdays(2)=28 ! MJT bug fix
      if (leap==1) then
        if(mod(iyr,4)==0)mdays(2)=29
        if(mod(iyr,100)==0)mdays(2)=28
        if(mod(iyr,400)==0)mdays(2)=29
      end if
      do while (mtimer_r>minsday*mdays(imo))
       mtimer_r=mtimer_r-minsday*mdays(imo)
       imo=imo+1
       if(imo>12)then
         imo=1
         iyr=iyr+1
         if (leap==1) then
           mdays(2)=28 ! MJT bug fix         
           if(mod(iyr,4)==0)mdays(2)=29
           if(mod(iyr,100)==0)mdays(2)=28
           if(mod(iyr,400)==0)mdays(2)=29
         end if
       endif
      enddo
      if(diag)write(6,*)'b datefix iyr,imo,iday,ihr,imins,mtimer_r: ',
     .                   iyr,imo,iday,ihr,imins,mtimer_r
      do while (mtimer_r>minsday)
       mtimer_r=mtimer_r-minsday
       iday=iday+1
      enddo
      if(diag)write(6,*)'c datefix iyr,imo,iday,ihr,imins,mtimer_r: ',
     .                   iyr,imo,iday,ihr,imins,mtimer_r

!     at this point mtimer_r has been reduced to fraction of a day
      mtimerh=mtimer_r/60
      mtimerm=mtimer_r-mtimerh*60  ! minutes left over
      ihr=ihr+mtimerh
      imins=imins+mtimerm
      if(imins==58.or.imins==59)then
!       allow for roundoff for real timer from old runs
        write(6,*)'*** imins increased to 60 from imins = ',imins
        imins=60
      endif
      if(imins>59)then
        imins=imins-60
        ihr=ihr+1
      endif
      if(diag)write(6,*)'d datefix iyr,imo,iday,ihr,imins,mtimer_r: ',
     .                   iyr,imo,iday,ihr,imins,mtimer_r
      if(ihr>23)then
        ihr=ihr-24
        iday=iday+1
      endif
      if(diag)write(6,*)'e datefix iyr,imo,iday,ihr,imins,mtimer_r: ',
     .                   iyr,imo,iday,ihr,imins,mtimer_r

      if(iday>mdays(imo))then
         iday=iday-mdays(imo)
         imo=imo+1
         if(imo>12)then
           imo=imo-12
           iyr=iyr+1
         endif
      endif

      kdate_r=iday+100*(imo+100*iyr)
      ktime_r=ihr*100+imins
      mtimer=0
      if(diag)write(6,*)'end datefix iyr,imo,iday,ihr,imins,mtimer_r: ',
     .                         iyr,imo,iday,ihr,imins,mtimer_r
      write(6,*)'leaving datefix kdate_r,ktime_r: ',kdate_r,ktime_r

      return
      end subroutine datefix

      end module infile