module cc_mpi
   implicit none
   private
   include 'newmpar.h'
   include 'mpif.h'

   integer, public :: myid ! Processor number
   ! These are just defined here to minimise changes from the ccshallow code.
   ! These could be parameters
   integer, public :: ipan, jpan !, npan
   integer, public :: ioff, joff, noff
   integer, private :: nxproc, nyproc

   integer, public, save, dimension(il_g,il_g,0:npanels) :: fproc
   integer, public, save, dimension(ifull_g) :: qproc


   ! These only need to be module variables for the overlap case
   ! when they have to keep values between boundsa and boundsb.
   ! For now leave them here.
   integer, dimension(2*nproc), save, private :: ireq
   integer, save, private :: nreq

   public :: bounds, boundsuv, ccmpi_setup, ccmpi_distribute, ccmpi_gather, &
             indp, indg, deptsync, intssync, start_log, end_log, check_dims, &
             log_on, log_off, log_setup, phys_loadbal, ccglobal_posneg, &
             ccglobal_sum, iq2iqg, indv_mpi, indglobal, readglobvar, writeglobvar
   private :: ccmpi_distribute2, ccmpi_distribute2i, ccmpi_distribute3, &
              ccmpi_gather2, ccmpi_gather3, checksize, get_dims, get_dims_gx,&
              ccglobal_posneg2, ccglobal_posneg3, ccglobal_sum2, ccglobal_sum3
   interface ccmpi_gather
      module procedure ccmpi_gather2, ccmpi_gather3
   end interface
   interface ccmpi_distribute
      module procedure ccmpi_distribute2, ccmpi_distribute2i, ccmpi_distribute3
   end interface
   interface bounds
      module procedure bounds2, bounds3
   end interface
   interface boundsuv
      module procedure boundsuv2, boundsuv3
   end interface
   interface ccglobal_posneg
      module procedure ccglobal_posneg2, ccglobal_posneg3
   end interface
   interface ccglobal_sum
      module procedure ccglobal_sum2, ccglobal_sum3
   end interface
   interface readglobvar
      module procedure readglobvar2, readglobvar3, readglobvar2i
   end interface
   interface writeglobvar
      module procedure writeglobvar2, writeglobvar3
   end interface

   ! Define neighbouring faces
   integer, parameter, private, dimension(0:npanels) ::    &
           n_e = (/ 2, 2, 4, 4, 0, 0 /), &
           n_w = (/ 5, 5, 1, 1, 3, 3 /), &
           n_n = (/ 1, 3, 3, 5, 5, 1 /), &
           n_s = (/ 4, 0, 0, 2, 2, 4 /)
   ! Do directions need to be swapped
   logical, parameter, private, dimension(0:npanels) ::    &
           swap_e = (/ .true., .false., .true., .false., .true., .false. /), &
           swap_w = (/ .false., .true., .false., .true., .false., .true. /), &
           swap_n = (/ .false., .true., .false., .true., .false., .true. /), &
           swap_s = (/ .true., .false., .true., .false., .true., .false. /)

   type bounds_info
      real, dimension(:), pointer :: sbuf, rbuf
      integer, dimension(:), pointer :: request_list
      integer, dimension(:), pointer :: send_list
      integer, dimension(:), pointer :: unpack_list
      integer, dimension(:), pointer :: request_list_uv
      integer, dimension(:), pointer :: send_list_uv
      integer, dimension(:), pointer :: unpack_list_uv
      ! Flag for whether u and v need to be swapped
      logical, dimension(:), pointer :: uv_swap, send_swap
      ! Number of points for each processor. Also double row versions.
      ! lenx is first row plux corner points.
      integer :: slen, rlen, slenx, rlenx, slen2, rlen2
      ! Number of points for each processor.
      integer :: slen_uv, rlen_uv, slen2_uv, rlen2_uv
      integer :: len
   end type bounds_info

   type(bounds_info), dimension(0:nproc-1), save :: bnds

   integer, private, save :: maxbuflen

   ! Flag whether processor region edge is a face edge.
   logical, public, save :: edge_w, edge_n, edge_s, edge_e

   ! Off processor departure points
   integer, private, save :: maxsize
   real, dimension(:,:,:), allocatable, public, save :: dpoints
   integer, dimension(:,:,:), allocatable, public, save :: dindex
   real, dimension(:,:),  allocatable, public, save :: sextra
   ! Number of points for each processor.
   integer, dimension(:), allocatable, public, save :: dslen, drlen

   ! True if processor is a nearest neighbour
   logical, dimension(0:nproc-1), public, save :: neighbour

   logical, public, save :: mydiag ! True if diagnostic point id, jd is in my region

   integer, public, save :: bounds_begin, bounds_end
   integer, public, save :: boundsa_begin, boundsa_end
   integer, public, save :: boundsb_begin, boundsb_end
   integer, public, save :: boundsuv_begin, boundsuv_end
   integer, public, save :: ints_begin, ints_end
   integer, public, save :: nonlin_begin, nonlin_end
   integer, public, save :: helm_begin, helm_end
   integer, public, save :: adjust_begin, adjust_end
   integer, public, save :: upglobal_begin, upglobal_end
   integer, public, save :: depts_begin, depts_end
   integer, public, save :: deptsync_begin, deptsync_end
   integer, public, save :: intssync_begin, intssync_end
   integer, public, save :: stag_begin, stag_end
   integer, public, save :: toij_begin, toij_end
   integer, public, save :: physloadbal_begin, physloadbal_end
   integer, public, save :: phys_begin, phys_end
   integer, public, save :: outfile_begin, outfile_end
   integer, public, save :: indata_begin, indata_end
   integer, public, save :: model_begin, model_end
   integer, public, save :: maincalc_begin, maincalc_end
   integer, public, save :: gather_begin, gather_end
   integer, public, save :: distribute_begin, distribute_end
   integer, public, save :: reduce_begin, reduce_end
   integer, public, save :: precon_begin, precon_end
   integer, public, save :: mpiwait_begin, mpiwait_end
#ifdef simple_timer
   public :: simple_timer_finalize
   integer, parameter :: nevents=25
   double precision, dimension(nevents), save :: tot_time = 0., start_time
   character(len=15), dimension(nevents), save :: event_name
#endif 

#ifdef mpilog
   public :: mpe_log_event, mpe_log_get_event_number, mpe_describe_state
   interface 
      function mpe_log_event (event, idata, string) result(val)
         integer, intent(in) :: event, idata
         character(len=*), intent(in) :: string
         integer :: val
      end function mpe_log_event
      function mpe_log_get_event_number() result(val)
         integer :: val
      end function mpe_log_get_event_number
      function mpe_describe_state(start,finish, name, color) result(val)
         integer, intent(in) :: start, finish
         character(len=*), intent(in) :: name, color
         integer :: val
      end function mpe_describe_state
   end interface
#endif

contains

   subroutine ccmpi_setup()
      use sumdd_m
      include 'xyzinfo.h'
      include 'xyzinfo_g.h'
      include 'map.h'
      include 'map_g.h'
      include 'vecsuv.h'
      include 'vecsuv_g.h'
      include 'latlong.h'
      include 'latlong_g.h'
      integer :: ierr

#ifdef uniform_decomp
      call proc_setup_uniform(npanels,ifull)
#else
      call proc_setup(npanels,ifull)
#endif

#ifdef DEBUG
      print*, "Grid", npan, ipan, jpan
      print*, "Offsets", myid, ioff, joff, noff
#endif

#ifdef uniform_decomp
      ! Faces may not line up properly so need extra factor here
      maxbuflen = (max(ipan,jpan)+4)*2*kl * 8 * 2
#else
      if ( nproc < npanels+1 ) then
         ! This is the maximum size, each face has 4 edges
         maxbuflen = npan*4*(il_g+4)*2*kl
      else
         maxbuflen = (max(ipan,jpan)+4)*2*kl
      end if
#endif

      ! Also do the initialisation for deptsync here
      allocate ( dslen(0:nproc-1), drlen(0:nproc-1) )
      if ( nproc == 1 ) then
         maxsize = 0 ! Not used in this case
      else
         ! 4 rows should be plenty (size is checked anyway).
         maxsize = 4*max(ipan,jpan)*npan*kl
      end if
      ! Off processor departure points
      allocate ( dpoints(4,maxsize,0:nproc-1), sextra(maxsize,0:nproc-1) )
      allocate ( dindex(2,maxsize,0:nproc-1) )
      
      if ( myid == 0 ) then
         call ccmpi_distribute(wts,wts_g)
         call ccmpi_distribute(em,em_g)
         call ccmpi_distribute(emu,emu_g)
         call ccmpi_distribute(emv,emv_g)
         call ccmpi_distribute(ax,ax_g)
         call ccmpi_distribute(bx,bx_g)
         call ccmpi_distribute(ay,ay_g)
         call ccmpi_distribute(by,by_g)
         call ccmpi_distribute(az,az_g)
         call ccmpi_distribute(bz,bz_g)
!!$         call ccmpi_distribute(axu,axu_g)
!!$         call ccmpi_distribute(ayu,ayu_g)
!!$         call ccmpi_distribute(azu,azu_g)
!!$         call ccmpi_distribute(bxv,bxv_g)
!!$         call ccmpi_distribute(byv,byv_g)
!!$         call ccmpi_distribute(bzv,bzv_g)
         call ccmpi_distribute(f,f_g)
         call ccmpi_distribute(fu,fu_g)
         call ccmpi_distribute(fv,fv_g)
         call ccmpi_distribute(dmdx,dmdx_g)
         call ccmpi_distribute(dmdy,dmdy_g)
         call ccmpi_distribute(x,x_g)
         call ccmpi_distribute(y,y_g)
         call ccmpi_distribute(z,z_g)
         call ccmpi_distribute(rlatt,rlatt_g)
         call ccmpi_distribute(rlongg,rlongg_g)
      else
         call ccmpi_distribute(wts)
         call ccmpi_distribute(em)
         call ccmpi_distribute(emu)
         call ccmpi_distribute(emv)
         call ccmpi_distribute(ax)
         call ccmpi_distribute(bx)
         call ccmpi_distribute(ay)
         call ccmpi_distribute(by)
         call ccmpi_distribute(az)
         call ccmpi_distribute(bz)
!!$         call ccmpi_distribute(axu)
!!$         call ccmpi_distribute(ayu)
!!$         call ccmpi_distribute(azu)
!!$         call ccmpi_distribute(bxv)
!!$         call ccmpi_distribute(byv)
!!$         call ccmpi_distribute(bzv)
         call ccmpi_distribute(f)
         call ccmpi_distribute(fu)
         call ccmpi_distribute(fv)
         call ccmpi_distribute(dmdx)
         call ccmpi_distribute(dmdy)
         call ccmpi_distribute(x)
         call ccmpi_distribute(y)
         call ccmpi_distribute(z)
         call ccmpi_distribute(rlatt)
         call ccmpi_distribute(rlongg)
      end if

      call bounds_setup()
      call bounds(em)
      call boundsuv(emu,emv)
      call boundsuv(ax,bx)
      call boundsuv(ay,by)
      call boundsuv(az,bz)
!!$      call bounds(axu)
!!$      call bounds(ayu)
!!$      call bounds(azu)
!!$      call bounds(bxv)
!!$      call bounds(byv)
!!$      call bounds(bzv)

#ifdef sumdd
!     operator MPI_SUMDR is created based on an external function DRPDR. 
      call MPI_OP_CREATE (DRPDR, .TRUE., MPI_SUMDR, ierr) 
#endif
   end subroutine ccmpi_setup

   subroutine ccmpi_distribute2(af,a1)
      ! Convert standard 1D arrays to face form and distribute to processors
      real, dimension(ifull), intent(out) :: af
      real, dimension(ifull_g), intent(in), optional :: a1
      integer :: i, j, n, iq, iqg, itag=0, iproc, ierr, count
      integer, dimension(MPI_STATUS_SIZE) :: status
!     Note ipfull = ipan*jpan*npan
      real, dimension(ipan*jpan*npan) :: sbuf
      integer :: npoff, ipoff, jpoff ! Offsets for target
      integer :: slen


      call start_log(distribute_begin)
!cdir iexpand(indp, indg)
      if ( myid == 0 .and. .not. present(a1) ) then
         print*, "Error: ccmpi_distribute argument required on proc 0"
         call MPI_Abort(MPI_COMM_WORLD,ierr)
      end if
      ! Copy internal region
      if ( myid == 0 ) then
         ! First copy own region
         do n=1,npan
            do j=1,jpan
!cdir nodep
               do i=1,ipan
                  iqg = indg(i,j,n)  ! True global index
                  iq = indp(i,j,n)
                  af(iq) = a1(iqg)
               end do
            end do
         end do
         ! Send appropriate regions to all other processes. In this version
         ! processor regions are no longer necessarily a continuous iq range.
         do iproc=1,nproc-1
            ! Panel range on the target processor
            call proc_region(iproc,ipoff,jpoff,npoff)
!            print*, "TARGET", ipoff, jpoff, npoff
            slen = 0
            do n=1,npan
               do j=1,jpan
                  do i=1,ipan
                     iq = i+ipoff + (j+jpoff-1)*il_g + (n-npoff)*il_g*il_g
                     slen = slen+1
                     sbuf(slen) = a1(iq)
                  end do
               end do
            end do
            call MPI_SSend( sbuf, slen, MPI_REAL, iproc, itag, &
                            MPI_COMM_WORLD, ierr )
         end do
      else ! myid /= 0
         call MPI_Recv( af, ipan*jpan*npan, MPI_REAL, 0, itag, &
                        MPI_COMM_WORLD, status, ierr )
         ! Check that the length is the expected value.
         call MPI_Get_count(status, MPI_REAL, count, ierr)
         if ( count /= ifull ) then
            print*, "Error, wrong length in ccmpi_distribute", myid, ifull, count
            call MPI_Abort(MPI_COMM_WORLD)
         end if

      end if
      call end_log(distribute_end)

   end subroutine ccmpi_distribute2

   subroutine ccmpi_distribute2i(af,a1)
      ! Convert standard 1D arrays to face form and distribute to processors
      integer, dimension(ifull), intent(out) :: af
      integer, dimension(ifull_g), intent(in), optional :: a1
      integer :: i, j, n, iq, iqg, itag=0, iproc, ierr, count
      integer, dimension(MPI_STATUS_SIZE) :: status
!     Note ipfull = ipan*jpan*npan
      integer, dimension(ipan*jpan*npan) :: sbuf
      integer :: npoff, ipoff, jpoff ! Offsets for target
      integer :: slen

      call start_log(distribute_begin)
!cdir iexpand(indp, indg)
      if ( myid == 0 .and. .not. present(a1) ) then
         print*, "Error: ccmpi_distribute argument required on proc 0"
         call MPI_Abort(MPI_COMM_WORLD,ierr)
      end if
      ! Copy internal region
      if ( myid == 0 ) then
         ! First copy own region
         do n=1,npan
            do j=1,jpan
!cdir nodep
               do i=1,ipan
                  iqg = indg(i,j,n)  ! True global index
                  iq = indp(i,j,n)
                  af(iq) = a1(iqg)
               end do
            end do
         end do
         ! Send appropriate regions to all other processes. In this version
         ! processor regions are no longer necessarily a continuous iq range.
         do iproc=1,nproc-1
            ! Panel range on the target processor
            call proc_region(iproc,ipoff,jpoff,npoff)
!            print*, "TARGET", ipoff, jpoff, npoff
            slen = 0
            do n=1,npan
               do j=1,jpan
                  do i=1,ipan
                     iq = i+ipoff + (j+jpoff-1)*il_g + (n-npoff)*il_g*il_g
                     slen = slen+1
                     sbuf(slen) = a1(iq)
                  end do
               end do
            end do
            call MPI_SSend( sbuf, slen, MPI_INTEGER, iproc, itag, &
                            MPI_COMM_WORLD, ierr )
         end do
      else ! myid /= 0
         call MPI_Recv( af, ipan*jpan*npan, MPI_INTEGER, 0, itag, &
                        MPI_COMM_WORLD, status, ierr )
         ! Check that the length is the expected value.
         call MPI_Get_count(status, MPI_INTEGER, count, ierr)
         if ( count /= ifull ) then
            print*, "Error, wrong length in ccmpi_distribute", myid, ifull, count
            call MPI_Abort(MPI_COMM_WORLD)
         end if

      end if
      call end_log(distribute_end)

   end subroutine ccmpi_distribute2i

   subroutine ccmpi_distribute3(af,a1)
      ! Convert standard 1D arrays to face form and distribute to processors
      ! This is also used for tracers, so second dimension is not necessarily
      ! the number of levels
      ! real, dimension(ifull,kl), intent(out) :: af
      ! real, dimension(ifull_g,kl), intent(in), optional :: a1
      real, dimension(:,:), intent(out) :: af
      real, dimension(:,:), intent(in), optional :: a1
      integer :: i, j, n, iq, iqg, itag=0, iproc, ierr, count
      integer, dimension(MPI_STATUS_SIZE) :: status
!     Note ipfull = ipan*jpan*npan. Isn't this just ifull?
!     Check?
      real, dimension(ipan*jpan*npan,size(af,2)) :: sbuf
      integer :: npoff, ipoff, jpoff ! Offsets for target
      integer :: slen

      call start_log(distribute_begin)
!cdir iexpand(indp, indg)
      if ( myid == 0 .and. .not. present(a1) ) then
         print*, "Error: ccmpi_distribute argument required on proc 0"
         call MPI_Abort(MPI_COMM_WORLD,ierr)
      end if
      ! Copy internal region
      if ( myid == 0 ) then
         ! First copy own region
         do n=1,npan
            do j=1,jpan
!cdir nodep
               do i=1,ipan
                  iqg = indg(i,j,n)  ! True global index
                  iq = indp(i,j,n)
                  af(iq,:) = a1(iqg,:)
               end do
            end do
         end do
         ! Send appropriate regions to all other processes. In this version
         ! processor regions are no longer necessarily a continuous iq range.
         do iproc=1,nproc-1
            ! Panel range on the target processor
            call proc_region(iproc,ipoff,jpoff,npoff)
!            print*, "TARGET", ipoff, jpoff, npoff
            slen = 0
            do n=1,npan
               do j=1,jpan
                  do i=1,ipan
                     iq = i+ipoff + (j+jpoff-1)*il_g + (n-npoff)*il_g*il_g
                     slen = slen+1
                     sbuf(slen,:) = a1(iq,:)
                  end do
               end do
            end do
            call MPI_SSend( sbuf, size(sbuf), MPI_REAL, iproc, itag, &
                            MPI_COMM_WORLD, ierr )
         end do
      else ! myid /= 0
         call MPI_Recv( af, size(af), MPI_REAL, 0, itag, &
                        MPI_COMM_WORLD, status, ierr )
         ! Check that the length is the expected value.
         call MPI_Get_count(status, MPI_REAL, count, ierr)
         if ( count /= size(af) ) then
            print*, "Error, wrong length in ccmpi_distribute", myid, size(af), count
            call MPI_Abort(MPI_COMM_WORLD)
         end if

      end if
      call end_log(distribute_end)

   end subroutine ccmpi_distribute3

   subroutine ccmpi_gather2(a,ag)
      ! Collect global arrays.

      real, dimension(ifull), intent(in) :: a
      real, dimension(ifull_g), intent(out), optional :: ag
      integer :: ierr, itag = 0, iproc
      integer, dimension(MPI_STATUS_SIZE) :: status
      real, dimension(ifull) :: abuf
      integer :: ipoff, jpoff, npoff
      integer :: i, j, n, iq, iqg


      call start_log(gather_begin)
!cdir iexpand(indp, indg, ind)
      if ( myid == 0 .and. .not. present(ag) ) then
         print*, "Error: ccmpi_gather argument required on proc 0"
         call MPI_Abort(MPI_COMM_WORLD,ierr)
      end if

      itag = itag + 1
      if ( myid == 0 ) then
         ! Use the face indices for unpacking
         do n=1,npan
            do j=1,jpan
!cdir nodep
               do i=1,ipan
                  iqg = indg(i,j,n)  ! True global index
                  iq = indp(i,j,n)
                  ag(iqg) = a(iq)
               end do
            end do
         end do
         do iproc=1,nproc-1
            call MPI_Recv( abuf, ipan*jpan*npan, MPI_REAL, iproc, itag, &
                        MPI_COMM_WORLD, status, ierr )
            ! Panel range on the source processor
            call proc_region(iproc,ipoff,jpoff,npoff)
            ! Use the face indices for unpacking
            do n=1,npan
               do j=1,jpan
!cdir nodep
                  do i=1,ipan
                     ! Global indices are i+ipoff, j+jpoff, n-npoff
                     iqg = indglobal(i+ipoff,j+jpoff,n-npoff) ! True global 1D index
                     iq = indp(i,j,n)
                     ag(iqg) = abuf(iq)
                  end do
               end do
            end do
         end do
      else
         abuf = a
         call MPI_SSend( abuf, ipan*jpan*npan, MPI_REAL, 0, itag, &
                         MPI_COMM_WORLD, ierr )
      end if

      call end_log(gather_end)

   end subroutine ccmpi_gather2

   subroutine ccmpi_gather3(a,ag)
      ! Collect global arrays.

      real, dimension(ifull,kl), intent(in) :: a
      real, dimension(ifull_g,kl), intent(out), optional :: ag
      integer :: ierr, itag = 0, iproc
      integer, dimension(MPI_STATUS_SIZE) :: status
      real, dimension(ifull,kl) :: abuf
      integer :: ipoff, jpoff, npoff
      integer :: i, j, n, iq, iqg

      call start_log(gather_begin)
!cdir iexpand(indp, indg, ind)
      if ( myid == 0 .and. .not. present(ag) ) then
         print*, "Error: ccmpi_gather argument required on proc 0"
         call MPI_Abort(MPI_COMM_WORLD,ierr)
      end if

      itag = itag + 1
      if ( myid == 0 ) then
         ! Use the face indices for unpacking
         do n=1,npan
            do j=1,jpan
               do i=1,ipan
                  iqg = indg(i,j,n)  ! True global index
                  iq = indp(i,j,n)
                  ag(iqg,:) = a(iq,:)
               end do
            end do
         end do
         do iproc=1,nproc-1
            call MPI_Recv( abuf, ipan*jpan*npan*kl, MPI_REAL, iproc, itag, &
                        MPI_COMM_WORLD, status, ierr )
            ! Panel range on the source processor
            call proc_region(iproc,ipoff,jpoff,npoff)
            ! Use the face indices for unpacking
            do n=1,npan
               do j=1,jpan
                  do i=1,ipan
                     iqg = indglobal(i+ipoff,j+jpoff,n-npoff) ! True global 1D index
                     iq = indp(i,j,n)
                     ag(iqg,:) = abuf(iq,:)
                  end do
               end do
            end do
         end do
      else
         abuf = a
         call MPI_SSend( abuf, ipan*jpan*npan*kl, MPI_REAL, 0, itag, &
                         MPI_COMM_WORLD, ierr )
      end if
      call end_log(gather_end)

   end subroutine ccmpi_gather3

   subroutine bounds_setup()

      include 'indices.h'
      include 'indices_g.h'
      integer :: n, nr, i, j, iq, iqx, count
      integer :: ierr, itag = 0, iproc, rproc, sproc
      integer, dimension(MPI_STATUS_SIZE,2*nproc) :: status
      integer :: iqg
      integer :: iext, iql, iloc, jloc, nloc
      logical :: swap

      ! Just set values that point to values within own processors region.
      ! Other values are set up later
      ! Set initial values to make sure missing values are caught properly.
!cdir iexpand(indp, indg, indv_mpi)
      in = huge(1)
      is = huge(1)
      iw = huge(1)
      ie = huge(1)
      inn = huge(1)
      iss = huge(1)
      iww = huge(1)
      iee = huge(1)
      ien = huge(1)
      ine = huge(1)
      ise = huge(1)
      iwn = huge(1)
      ieu = huge(1)
      iwu = huge(1)
      inv = huge(1)
      isv = huge(1)
      ieeu = huge(1)
      iwwu = huge(1)
      innv = huge(1)
      issv = huge(1)
      lwws = huge(1)
      lws = huge(1)
      lwss = huge(1)
      les = huge(1)
      lees = huge(1)
      less = huge(1)
      lwwn = huge(1)
      lwnn = huge(1)
      leen = huge(1)
      lenn = huge(1)
      lsww = huge(1)
      lsw = huge(1)
      lssw = huge(1)
      lsee = huge(1)
      lsse = huge(1)
      lnww = huge(1)
      lnw = huge(1)
      lnnw = huge(1)
      lnee = huge(1)
      lnne = huge(1)
      do n=1,npan
         do j=1,jpan
            do i=1,ipan
               iq = indp(i,j,n)   ! Local
               iqg = indg(i,j,n)  ! Global

               iqx = in_g(iqg)    ! Global neighbour index
               rproc = qproc(iqx) ! Processor that has this point
               if ( rproc == myid ) then ! Just copy the value
                  ! Convert global iqx to local value
                  call indv_mpi(iqx,iloc,jloc,nloc)
                  in(iq) = indp(iloc,jloc,nloc)
               end if
               iqx = inn_g(iqg)    ! Global neighbour index
               rproc = qproc(iqx) ! Processor that has this point
               if ( rproc == myid ) then ! Just copy the value
                  ! Convert global iqx to local value
                  call indv_mpi(iqx,iloc,jloc,nloc)
                  inn(iq) = indp(iloc,jloc,nloc)
               end if

               iqx = is_g(iqg)    ! Global neighbour index
               rproc = qproc(iqx) ! Processor that has this point
               if ( rproc == myid ) then ! Just copy the value
                  ! Convert global iqx to local value
                  call indv_mpi(iqx,iloc,jloc,nloc)
                  is(iq) = indp(iloc,jloc,nloc)
               end if
               iqx = iss_g(iqg)    ! Global neighbour index
               rproc = qproc(iqx) ! Processor that has this point
               if ( rproc == myid ) then ! Just copy the value
                  ! Convert global iqx to local value
                  call indv_mpi(iqx,iloc,jloc,nloc)
                  iss(iq) = indp(iloc,jloc,nloc)
               end if

               iqx = ie_g(iqg)    ! Global neighbour index
               rproc = qproc(iqx) ! Processor that has this point
               if ( rproc == myid ) then ! Just copy the value
                  ! Convert global iqx to local value
                  call indv_mpi(iqx,iloc,jloc,nloc)
                  ie(iq) = indp(iloc,jloc,nloc)
               end if
               iqx = iee_g(iqg)    ! Global neighbour index
               rproc = qproc(iqx) ! Processor that has this point
               if ( rproc == myid ) then ! Just copy the value
                  ! Convert global iqx to local value
                  call indv_mpi(iqx,iloc,jloc,nloc)
                  iee(iq) = indp(iloc,jloc,nloc)
               end if

               iqx = iw_g(iqg)    ! Global neighbour index
               rproc = qproc(iqx) ! Processor that has this point
               if ( rproc == myid ) then ! Just copy the value
                  ! Convert global iqx to local value
                  call indv_mpi(iqx,iloc,jloc,nloc)
                  iw(iq) = indp(iloc,jloc,nloc)
               end if
               iqx = iww_g(iqg)    ! Global neighbour index
               rproc = qproc(iqx) ! Processor that has this point
               if ( rproc == myid ) then ! Just copy the value
                  ! Convert global iqx to local value
                  call indv_mpi(iqx,iloc,jloc,nloc)
                  iww(iq) = indp(iloc,jloc,nloc)
               end if

               ! Note that the model only needs a limited set of the diagonal
               ! index arrays
               iqx = ine_g(iqg)    ! Global neighbour index
               rproc = qproc(iqx) ! Processor that has this point
               if ( rproc == myid ) then ! Just copy the value
                  ! Convert global iqx to local value
                  call indv_mpi(iqx,iloc,jloc,nloc)
                  ine(iq) = indp(iloc,jloc,nloc)
               end if

               iqx = ise_g(iqg)    ! Global neighbour index
               rproc = qproc(iqx) ! Processor that has this point
               if ( rproc == myid ) then ! Just copy the value
                  ! Convert global iqx to local value
                  call indv_mpi(iqx,iloc,jloc,nloc)
                  ise(iq) = indp(iloc,jloc,nloc)
               end if

               iqx = ien_g(iqg)    ! Global neighbour index
               rproc = qproc(iqx) ! Processor that has this point
               if ( rproc == myid ) then ! Just copy the value
                  ! Convert global iqx to local value
                  call indv_mpi(iqx,iloc,jloc,nloc)
                  ien(iq) = indp(iloc,jloc,nloc)
               end if

               iqx = iwn_g(iqg)    ! Global neighbour index
               rproc = qproc(iqx) ! Processor that has this point
               if ( rproc == myid ) then ! Just copy the value
                  ! Convert global iqx to local value
                  call indv_mpi(iqx,iloc,jloc,nloc)
                  iwn(iq) = indp(iloc,jloc,nloc)
               end if

            end do
         end do
      end do

      ! Correct within the same face only (not necessarily the same
      ! processor, but will be corrected later).
      ieu = ie
      iwu = iw
      inv = in
      isv = is

      ! Initialise the edge variables
      edge_w = ioff == 0
      edge_s = joff == 0
      edge_n = joff == il_g - jpan
      edge_e = ioff == il_g - ipan

      ! Allocate array to hold values for each processor, including self.
!      allocate(bnds(0:nproc-1))
!      allocate(ireq(2*nproc))

      nr = 1

      bnds(:)%len = 0
      bnds(:)%rlen = 0
      bnds(:)%slen = 0
      bnds(:)%rlenx = 0
      bnds(:)%slenx = 0
      bnds(:)%rlen2 = 0
      bnds(:)%slen2 = 0


!     In the first pass through, set up list of points to be requested from
!     other processors. These points are placed in the "iextra" region at the
!     end of arrays. The indirect indices are updated to point into this 
!     region.
      iext = 0
      do n=1,npan

         !     Start with W edge
         i = 1
         do j=1,jpan
            ! 1D code takes care of corners separately at the end so only goes
            ! over 1,jpan here.
            iq = indg(i,j,n)
            iqx = iw_g(iq)

            ! iqx is the global index of the required neighbouring point.

            ! Which processor has this point
            rproc = qproc(iqx)
            if ( rproc == myid ) cycle ! Don't add points already on this proc.
            ! Add this point to request list
            call check_bnds_alloc(rproc, iext)
            bnds(rproc)%rlen = bnds(rproc)%rlen + 1
            bnds(rproc)%request_list(bnds(rproc)%rlen) = iqx
            ! Increment extended region index
            iext = iext + 1
            bnds(rproc)%unpack_list(bnds(rproc)%rlen) = iext
            iql = indp(i,j,n)  !  Local index
            iw(iql) = ifull+iext
         end do

         !     N edge
         j=jpan
         do i=1,ipan
            iq = indg(i,j,n)
            iqx = in_g(iq)

            ! Which processor has this point
            rproc = qproc(iqx)
            if ( rproc == myid ) cycle ! Don't add points already on this proc.
            ! Add this point to request list
            call check_bnds_alloc(rproc, iext)
            bnds(rproc)%rlen = bnds(rproc)%rlen + 1
            bnds(rproc)%request_list(bnds(rproc)%rlen) = iqx
            ! Increment extended region index
            iext = iext + 1
            bnds(rproc)%unpack_list(bnds(rproc)%rlen) = iext
            iql = indp(i,j,n)  !  Local index
            in(iql) = ifull+iext
         end do

         !     E edge
         i = ipan
         do j=1,jpan
            iq = indg(i,j,n)
            iqx = ie_g(iq)

            ! Which processor has this point
            rproc = qproc(iqx)
            if ( rproc == myid ) cycle ! Don't add points already on this proc.
            ! Add this point to request list
            call check_bnds_alloc(rproc, iext)
            bnds(rproc)%rlen = bnds(rproc)%rlen + 1
            bnds(rproc)%request_list(bnds(rproc)%rlen) = iqx
            ! Increment extended region index
            iext = iext + 1
            bnds(rproc)%unpack_list(bnds(rproc)%rlen) = iext
            iql = indp(i,j,n)  !  Local index
            ie(iql) = ifull+iext
         end do

         !     S edge
         j=1
         do i=1,ipan
            iq = indg(i,j,n)
            iqx = is_g(iq)

            ! Which processor has this point
            rproc = qproc(iqx)
            if ( rproc == myid ) cycle ! Don't add points already on this proc.
            ! Add this point to request list
            call check_bnds_alloc(rproc, iext)
            bnds(rproc)%rlen = bnds(rproc)%rlen + 1
            bnds(rproc)%request_list(bnds(rproc)%rlen) = iqx
            ! Increment extended region index
            iext = iext + 1
            bnds(rproc)%unpack_list(bnds(rproc)%rlen) = iext
            iql = indp(i,j,n)  !  Local index
            is(iql) = ifull+iext
         end do
      end do ! n=1,npan

      bnds(:)%rlenx = bnds(:)%rlen  ! so that they're appended.
      
!     Now handle the special corner values that need to be remapped
!     This adds to rlen, so needs to come before the _XX stuff.
      do n=1,npan
         ! NE, EN
         iq = indp(ipan,jpan,n)
         iqg = indg(ipan,jpan,n)
!        This might matter for leen etc but not here
!         if ( edge_e .and. edge_n ) then
!            ! This is a real vertex
         iqx = ine_g(iqg)
         ! Which processor has this point
         rproc = qproc(iqx)
         if ( rproc /= myid ) then ! Add to list
            call check_bnds_alloc(rproc, iext)
            bnds(rproc)%rlenx = bnds(rproc)%rlenx + 1
            bnds(rproc)%request_list(bnds(rproc)%rlenx) = iqx
            ! Increment extended region index
            iext = iext + 1
            bnds(rproc)%unpack_list(bnds(rproc)%rlenx) = iext
            ine(iq) = ifull+iext
         end if

         iqx = ien_g(iqg)
         ! Which processor has this point
         rproc = qproc(iqx)
         if ( rproc /= myid ) then ! Add to list
            call check_bnds_alloc(rproc, iext)
            bnds(rproc)%rlenx = bnds(rproc)%rlenx + 1
            bnds(rproc)%request_list(bnds(rproc)%rlenx) = iqx
            ! Increment extended region index
            iext = iext + 1
            bnds(rproc)%unpack_list(bnds(rproc)%rlenx) = iext
            ien(iq) = ifull+iext
         end if

         iq = indp(ipan,1,n)
         iqg = indg(ipan,1,n)
         iqx = ise_g(iqg)
         ! Which processor has this point
         rproc = qproc(iqx)
         if ( rproc /= myid ) then ! Add to list
            call check_bnds_alloc(rproc, iext)
            bnds(rproc)%rlenx = bnds(rproc)%rlenx + 1
            bnds(rproc)%request_list(bnds(rproc)%rlenx) = iqx
            ! Increment extended region index
            iext = iext + 1
            bnds(rproc)%unpack_list(bnds(rproc)%rlenx) = iext
            ise(iq) = ifull+iext
         end if

         iq = indp(1,jpan,n)
         iqg = indg(1,jpan,n)
         iqx = iwn_g(iqg)
         ! Which processor has this point
         rproc = qproc(iqx)
         if ( rproc /= myid ) then ! Add to list
            call check_bnds_alloc(rproc, iext)
            bnds(rproc)%rlenx = bnds(rproc)%rlenx + 1
            bnds(rproc)%request_list(bnds(rproc)%rlenx) = iqx
            ! Increment extended region index
            iext = iext + 1
            bnds(rproc)%unpack_list(bnds(rproc)%rlenx) = iext
            iwn(iq) = ifull+iext
         end if

!        Special vertex arrays.
!        First order ws, es, sw, nw

         iq = indp(1,1,n)
         iqg = indg(1,1,n)
         if ( edge_w .and. edge_s ) then
            iqx = lws_g(n-noff)  ! This is the true face index
         else if ( edge_w ) then
            ! Middle of W edge, use is first because this is on the same
            ! face
            iqx = iw_g(is_g(iqg))
         else
            iqx = is_g(iw_g(iqg))
         end if
         call fix_index(iqx,lws,n,bnds,iext)

         if ( edge_w .and. edge_s ) then
            iqx = lsw_g(n-noff)  ! This is the true face index
         else if ( edge_w ) then
            ! Middle of W edge, use is first because this is on the same
            ! face
            iqx = iw_g(is_g(iqg))
         else
            iqx = is_g(iw_g(iqg))
         end if
         call fix_index(iqx,lsw,n,bnds,iext)

         iq = indp(ipan,1,n)
         iqg = indg(ipan,1,n)
         if ( edge_e .and. edge_s ) then
            iqx = les_g(n-noff)  ! This is the true face index
         else if ( edge_e ) then
            ! Middle of E edge, use is first because this is on the same
            ! face
            iqx = ie_g(is_g(iqg))
         else
            iqx = is_g(ie_g(iqg))
         end if
         call fix_index(iqx,les,n,bnds,iext)

         iq = indp(1,jpan,n)
         iqg = indg(1,jpan,n)
         if ( edge_w .and. edge_n ) then
            iqx = lnw_g(n-noff)  ! This is the true face index
         else if ( edge_w ) then
            ! Middle of W edge, use in first because this is on the same
            ! face
            iqx = iw_g(in_g(iqg))
         else
            iqx = in_g(iw_g(iqg))
         end if
         call fix_index(iqx,lnw,n,bnds,iext)

      end do

!     Now set up the second row
      bnds(:)%rlen2 = bnds(:)%rlenx  ! so that they're appended.
      do n=1,npan

         !     Start with W edge
         i = 1
         do j=1,jpan
            iq = indg(i,j,n)
            iqx = iww_g(iq)

            ! Which processor has this point
            rproc = qproc(iqx)
            if ( rproc == myid ) cycle ! Don't add points already on this proc.
            ! Add this point to request list
            call check_bnds_alloc(rproc, iext)
            bnds(rproc)%rlen2 = bnds(rproc)%rlen2 + 1
            bnds(rproc)%request_list(bnds(rproc)%rlen2) = iqx
            ! Increment extended region index
            iext = iext + 1
            bnds(rproc)%unpack_list(bnds(rproc)%rlen2) = iext
            iql = indp(i,j,n)  !  Local index
            iww(iql) = ifull+iext
         end do

         !     N edge
         j=jpan
         do i=1,ipan
            iq = indg(i,j,n)
            iqx = inn_g(iq)

            ! Which processor has this point
            rproc = qproc(iqx)
            if ( rproc == myid ) cycle ! Don't add points already on this proc.
            ! Add this point to request list
            call check_bnds_alloc(rproc, iext)
            bnds(rproc)%rlen2 = bnds(rproc)%rlen2 + 1
            bnds(rproc)%request_list(bnds(rproc)%rlen2) = iqx
            ! Increment extended region index
            iext = iext + 1
            bnds(rproc)%unpack_list(bnds(rproc)%rlen2) = iext
            iql = indp(i,j,n)  !  Local index
            inn(iql) = ifull+iext
         end do

         !     E edge
         i = ipan
         do j=1,jpan
            iq = indg(i,j,n)
            iqx = iee_g(iq)

            ! Which processor has this point
            rproc = qproc(iqx)
            if ( rproc == myid ) cycle ! Don't add points already on this proc.
            ! Add this point to request list
            call check_bnds_alloc(rproc, iext)
            bnds(rproc)%rlen2 = bnds(rproc)%rlen2 + 1
            bnds(rproc)%request_list(bnds(rproc)%rlen2) = iqx
            ! Increment extended region index
            iext = iext + 1
            bnds(rproc)%unpack_list(bnds(rproc)%rlen2) = iext
            iql = indp(i,j,n)  !  Local index
            iee(iql) = ifull+iext
         end do

         !     S edge
         j=1
         do i=1,ipan
            iq = indg(i,j,n)
            iqx = iss_g(iq)

            ! Which processor has this point
            rproc = qproc(iqx)
            if ( rproc == myid ) cycle ! Don't add points already on this proc.
            ! Add this point to request list
            call check_bnds_alloc(rproc, iext)
            bnds(rproc)%rlen2 = bnds(rproc)%rlen2 + 1
            bnds(rproc)%request_list(bnds(rproc)%rlen2) = iqx
            ! Increment extended region index
            iext = iext + 1
            bnds(rproc)%unpack_list(bnds(rproc)%rlen2) = iext
            iql = indp(i,j,n)  !  Local index
            iss(iql) = ifull+iext
         end do
      end do ! n=1,npan

!     Now handle the second order special corner values
      do n=1,npan
         ! NE corner, lnee, leen, lenn, lnne
         iqg = indg(ipan,jpan,n)
         if ( edge_n .and. edge_e ) then
            call fix_index2(lnee_g(n-noff),lnee,n,bnds,iext)
            call fix_index2(leen_g(n-noff),leen,n,bnds,iext)
            call fix_index2(lenn_g(n-noff),lenn,n,bnds,iext)
            call fix_index2(lnne_g(n-noff),lnne,n,bnds,iext)
         else if ( edge_e ) then
            ! Use in first because it'll be on same face.
            call fix_index2(iee_g(in_g(iqg)),lnee,n,bnds,iext)
            leen(n) = lnee(n)
            call fix_index2(ie_g(inn_g(iqg)),lenn,n,bnds,iext)
            lnne(n) = lenn(n)
         else
            ! Use ie first
            call fix_index2(in_g(iee_g(iqg)),lnee,n,bnds,iext)
            leen(n) = lnee(n)
            call fix_index2(inn_g(ie_g(iqg)),lenn,n,bnds,iext)
            lnne(n) = lenn(n)
         end if

         ! NW corner, lnww, lwwn, lwnn, lnnw
         iqg = indg(1,jpan,n)
         if ( edge_n .and. edge_w ) then
            call fix_index2(lnww_g(n-noff),lnww,n,bnds,iext)
            call fix_index2(lwwn_g(n-noff),lwwn,n,bnds,iext)
            call fix_index2(lwnn_g(n-noff),lwnn,n,bnds,iext)
            call fix_index2(lnnw_g(n-noff),lnnw,n,bnds,iext)
         else if ( edge_w ) then
            ! Use in first because it'll be on same face.
            call fix_index2(iww_g(in_g(iqg)),lnww,n,bnds,iext)
            lwwn(n) = lnww(n)
            call fix_index2(iw_g(inn_g(iqg)),lwnn,n,bnds,iext)
            lnnw(n) = lwnn(n)
         else
            ! Use iw first
            call fix_index2(in_g(iww_g(iqg)),lnww,n,bnds,iext)
            lwwn(n) = lnww(n)
            call fix_index2(inn_g(iw_g(iqg)),lwnn,n,bnds,iext)
            lnnw(n) = lwnn(n)
         end if

         ! SE corner, lsee, lees, less, lsse
         iqg = indg(ipan,1,n)
         if ( edge_s .and. edge_e ) then
            call fix_index2(lsee_g(n-noff),lsee,n,bnds,iext)
            call fix_index2(lees_g(n-noff),lees,n,bnds,iext)
            call fix_index2(less_g(n-noff),less,n,bnds,iext)
            call fix_index2(lsse_g(n-noff),lsse,n,bnds,iext)
         else if ( edge_e ) then
            ! Use is first because it'll be on same face.
            call fix_index2(iee_g(is_g(iqg)),lsee,n,bnds,iext)
            lees(n) = lsee(n)
            call fix_index2(ie_g(iss_g(iqg)),less,n,bnds,iext)
            lsse(n) = less(n)
         else
            ! Use ie first
            call fix_index2(is_g(iee_g(iqg)),lsee,n,bnds,iext)
            lees(n) = lsee(n)
            call fix_index2(iss_g(ie_g(iqg)),less,n,bnds,iext)
            lsse(n) = less(n)
         end if

         ! SW corner, lsww, lwws, lwss, lssw
         iqg = indg(1,1,n)
         if ( edge_s .and. edge_w ) then
            call fix_index2(lsww_g(n-noff),lsww,n,bnds,iext)
            call fix_index2(lwws_g(n-noff),lwws,n,bnds,iext)
            call fix_index2(lwss_g(n-noff),lwss,n,bnds,iext)
            call fix_index2(lssw_g(n-noff),lssw,n,bnds,iext)
         else if ( edge_w ) then
            ! Use is first because it'll be on same face.
            call fix_index2(iww_g(is_g(iqg)),lsww,n,bnds,iext)
            lwws(n) = lsww(n)
            call fix_index2(iw_g(iss_g(iqg)),lwss,n,bnds,iext)
            lssw(n) = lwss(n)
         else
            ! Use iw first
            call fix_index2(is_g(iww_g(iqg)),lsww,n,bnds,iext)
            lwws(n) = lsww(n)
            call fix_index2(iss_g(iw_g(iqg)),lwss,n,bnds,iext)
            lssw(n) = lwss(n)
         end if

      end do

!     Indices that are missed above (should be a better way to get these)
      do n=1,npan
         do j=1,jpan
            iww(indp(2,j,n)) = iw(indp(1,j,n))
            iee(indp(ipan-1,j,n)) = ie(indp(ipan,j,n))
         end do
         do i=1,ipan
            iss(indp(i,2,n)) = is(indp(i,1,n))
            inn(indp(i,jpan-1,n)) = in(indp(i,jpan,n))
         end do
      end do

!     Set up the diagonal index arrays. Most of the points here will have
!     already been added to copy lists above. The corners are handled
!     separately here. This means some points may be copied twice but it's
!     a small overhead.
      do n=1,npan
         do j=1,jpan
            do i=1,ipan
               iq = indp(i,j,n)   ! Local
               ! Except at corners, ien = ine etc.
               if ( i < ipan ) then
                  ! ie will be defined
                  ine(iq) = in(ie(iq))
                  ise(iq) = is(ie(iq))
               else
                  ! i = ipan, ie will have been remapped
                  if ( j > 1 )    ise(iq) = ie(is(iq))
                  if ( j < jpan ) ine(iq) = ie(in(iq))
               end if
               if ( j < jpan ) then
                  ien(iq) = ie(in(iq))
                  iwn(iq) = iw(in(iq))
               else
                  if ( i < ipan) ien(iq) = in(ie(iq))
                  if ( i > 1 )   iwn(iq) = in(iw(iq))
               end if
            end do
         end do
      end do

      if ( iext > iextra ) then
         print*, "IEXT too large", iext, iextra
         call MPI_Abort(MPI_COMM_WORLD)
      end if



!     Now, for each processor send the list of points I want.
!     The state of being a neighbour is reflexive so only expect to
!     recv from those processors I send to (are there grid arrangements for
!     which this would not be true?)
!     Get the complete request lists by using rlen2
      nreq = 0
      do iproc = 1,nproc-1  !
         sproc = modulo(myid+iproc,nproc)  ! Send to
         if (bnds(sproc)%rlen2 > 0 ) then
            ! Send list of requests
            nreq = nreq + 1
            call MPI_ISend( bnds(sproc)%request_list(1), bnds(sproc)%rlen2, &
                 MPI_INTEGER, sproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
            nreq = nreq + 1
            ! Use the maximum size in the recv call.
            call MPI_IRecv( bnds(sproc)%send_list(1), bnds(sproc)%len, &
                 MPI_INTEGER, sproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
         end if
      end do
      if ( nreq > 0 ) then
         call MPI_Waitall(nreq,ireq,status,ierr)
      end if

!     Now get the actual sizes from the status
      nreq = 0
      do iproc = 1,nproc-1  !
         sproc = modulo(myid+iproc,nproc)  ! Recv from
         if (bnds(sproc)%rlen2 > 0 ) then
            ! To get recv status, advance nreq by 2
            nreq = nreq + 2
            call MPI_Get_count(status(1,nreq), MPI_INTEGER, count, ierr)
            ! This the number of points I have to send to rproc.
            bnds(sproc)%slen2 = count
         end if
      end do

!     For rlen and rlenx, just communicate the lengths. The indices have 
!     already been taken care of.
      nreq = 0
      do iproc = 1,nproc-1  !
         ! Send and recv from same proc
         sproc = modulo(myid+iproc,nproc)  ! Send to
         if (bnds(sproc)%rlen > 0 ) then
            nreq = nreq + 1
            call MPI_ISend( bnds(sproc)%rlen, 1, &
                 MPI_INTEGER, sproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
            nreq = nreq + 1
            call MPI_IRecv( bnds(sproc)%slen, 1, &
                 MPI_INTEGER, sproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
         end if
      end do
      if ( nreq > 0 ) then
         call MPI_Waitall(nreq,ireq,status,ierr)
      end if

      nreq = 0
      do iproc = 1,nproc-1  !
         ! Send and recv from same proc
         sproc = modulo(myid+iproc,nproc)  ! Send to
         if (bnds(sproc)%rlenx > 0 ) then
            nreq = nreq + 1
            call MPI_ISend( bnds(sproc)%rlenx, 1, &
                 MPI_INTEGER, sproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
            nreq = nreq + 1
            call MPI_IRecv( bnds(sproc)%slenx, 1, &
                 MPI_INTEGER, sproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
         end if
      end do
      if ( nreq > 0 ) then
         call MPI_Waitall(nreq,ireq,status,ierr)
      end if

!     Start of UV section

      bnds(:)%rlen_uv = 0
      bnds(:)%slen_uv = 0

!     In the first pass through, set up list of points to be requested from
!     other processors. In the 1D code values on the same processor are
!     copied only if they have to be swapped.
!     This only makes a difference on 1, 2 or 3 processors.

      iext = 0
      do n=1,npan

         !     Start with W edge, U values
         i = 1
         do j=1,jpan
            iqg = indg(i,j,n)
            iqx = iw_g(iqg)
            ! Which processor has this point
            rproc = qproc(iqx)
            ! Only need to add to bounds region if it's on another processor
            ! or if it's on this processor and needs to be swapped.
            ! Decide if u/v need to be swapped. My face is n-noff
            swap = edge_w .and. swap_w(n-noff)
            if ( rproc == myid .and. .not. swap ) cycle
            call check_bnds_alloc(rproc, iext)
            bnds(rproc)%rlen_uv = bnds(rproc)%rlen_uv + 1
            bnds(rproc)%request_list_uv(bnds(rproc)%rlen_uv) = iqx
            ! Increment extended region index
            iext = iext + 1
            bnds(rproc)%unpack_list_uv(bnds(rproc)%rlen_uv) = iext
            iql = indp(i,j,n)  !  Local index
            iwu(iql) = ifull+iext
            bnds(rproc)%uv_swap(bnds(rproc)%rlen_uv) = swap
         end do

         !     N edge (V)
         j=jpan
         do i=1,ipan
            iqg = indg(i,j,n)
            iqx = in_g(iqg)
            rproc = qproc(iqx)
            swap = edge_n .and. swap_n(n-noff)
            if ( rproc == myid .and. .not. swap ) cycle
            ! Add this point to request list
            call check_bnds_alloc(rproc, iext)
            bnds(rproc)%rlen_uv = bnds(rproc)%rlen_uv + 1
            ! to show that this is v rather than u, flip sign
            bnds(rproc)%request_list_uv(bnds(rproc)%rlen_uv) = -iqx
            ! Increment extended region index
            iext = iext + 1
            bnds(rproc)%unpack_list_uv(bnds(rproc)%rlen_uv) = -iext
            iql = indp(i,j,n)  !  Local index
            inv(iql) = ifull+iext
            bnds(rproc)%uv_swap(bnds(rproc)%rlen_uv) = swap
         end do

         !     E edge, U
         i = ipan
         do j=1,jpan
            iqg = indg(i,j,n)
            iqx = ie_g(iqg)
            rproc = qproc(iqx)
            swap = edge_e .and. swap_e(n-noff)
            if ( rproc == myid .and. .not. swap ) cycle
            ! Add this point to request list
            call check_bnds_alloc(rproc, iext)
            bnds(rproc)%rlen_uv = bnds(rproc)%rlen_uv + 1
            bnds(rproc)%request_list_uv(bnds(rproc)%rlen_uv) = iqx
            ! Increment extended region index
            iext = iext + 1
            bnds(rproc)%unpack_list_uv(bnds(rproc)%rlen_uv) = iext
            iql = indp(i,j,n)  !  Local index
            ieu(iql) = ifull+iext
            bnds(rproc)%uv_swap(bnds(rproc)%rlen_uv) = swap
         end do

         !     S edge, V
         j=1
         do i=1,ipan
            iqg = indg(i,j,n)
            iqx = is_g(iqg)
            rproc = qproc(iqx)
            swap = edge_s .and. swap_s(n-noff)
            if ( rproc == myid .and. .not. swap ) cycle
            call check_bnds_alloc(rproc, iext)
            bnds(rproc)%rlen_uv = bnds(rproc)%rlen_uv + 1
            bnds(rproc)%request_list_uv(bnds(rproc)%rlen_uv) = -iqx
            ! Increment extended region index
            iext = iext + 1
            bnds(rproc)%unpack_list_uv(bnds(rproc)%rlen_uv) = -iext
            iql = indp(i,j,n)  !  Local index
            isv(iql) = ifull+iext
            bnds(rproc)%uv_swap(bnds(rproc)%rlen_uv) = swap
         end do
      end do ! n=1,npan

!     Second pass
      bnds(:)%rlen2_uv = bnds(:)%rlen_uv
      bnds(:)%slen2_uv = bnds(:)%slen_uv
      ieeu = iee
      iwwu = iww
      innv = inn
      issv = iss

      do n=1,npan

         !     Start with W edge, U values
         i = 1
         do j=1,jpan
            iqg = indg(i,j,n)
            iqx = iww_g(iqg)
            ! Which processor has this point
            rproc = qproc(iqx)
            swap = edge_w .and. swap_w(n-noff)
            if ( rproc == myid .and. .not. swap ) cycle
            ! Add this point to request list
            call check_bnds_alloc(rproc,iext)
            bnds(rproc)%rlen2_uv = bnds(rproc)%rlen2_uv + 1
            bnds(rproc)%request_list_uv(bnds(rproc)%rlen2_uv) = iqx
            ! Increment extended region index
            iext = iext + 1
            bnds(rproc)%unpack_list_uv(bnds(rproc)%rlen2_uv) = iext
            iql = indp(i,j,n)  !  Local index
            iwwu(iql) = ifull+iext
            ! Decide if u/v need to be swapped. My face is n-noff
            bnds(rproc)%uv_swap(bnds(rproc)%rlen2_uv) = swap
         end do

         !     N edge (V)
         j=jpan
         do i=1,ipan
            iqg = indg(i,j,n)
            iqx = inn_g(iqg)
            rproc = qproc(iqx)
            swap = edge_n .and. swap_n(n-noff)
            if ( rproc == myid .and. .not. swap ) cycle
            ! Add this point to request list
            call check_bnds_alloc(rproc,iext)
            bnds(rproc)%rlen2_uv = bnds(rproc)%rlen2_uv + 1
            ! to show that this is v rather than u, flip sign
            bnds(rproc)%request_list_uv(bnds(rproc)%rlen2_uv) = -iqx
            ! Increment extended region index
            iext = iext + 1
            bnds(rproc)%unpack_list_uv(bnds(rproc)%rlen2_uv) = -iext
            iql = indp(i,j,n)  !  Local index
            innv(iql) = ifull+iext
            bnds(rproc)%uv_swap(bnds(rproc)%rlen2_uv) = swap
         end do

         !     E edge, U
         i = ipan
         do j=1,jpan
            iqg = indg(i,j,n)
            iqx = iee_g(iqg)
            rproc = qproc(iqx)
            swap = edge_e .and. swap_e(n-noff)
            if ( rproc == myid .and. .not. swap ) cycle
            ! Add this point to request list
            call check_bnds_alloc(rproc,iext)
            bnds(rproc)%rlen2_uv = bnds(rproc)%rlen2_uv + 1
            bnds(rproc)%request_list_uv(bnds(rproc)%rlen2_uv) = iqx
            ! Increment extended region index
            iext = iext + 1
            bnds(rproc)%unpack_list_uv(bnds(rproc)%rlen2_uv) = iext
            iql = indp(i,j,n)  !  Local index
            ieeu(iql) = ifull+iext
            bnds(rproc)%uv_swap(bnds(rproc)%rlen2_uv) = swap
         end do

         !     S edge, V
         j=1
         do i=1,ipan
            iqg = indg(i,j,n)
            iqx = iss_g(iqg)
            rproc = qproc(iqx)
            swap = edge_s .and. swap_s(n-noff)
            if ( rproc == myid .and. .not. swap ) cycle
            call check_bnds_alloc(rproc,iext)
            bnds(rproc)%rlen2_uv = bnds(rproc)%rlen2_uv + 1
            bnds(rproc)%request_list_uv(bnds(rproc)%rlen2_uv) = -iqx
            ! Increment extended region index
            iext = iext + 1
            bnds(rproc)%unpack_list_uv(bnds(rproc)%rlen2_uv) = -iext
            iql = indp(i,j,n)  !  Local index
            issv(iql) = ifull+iext
            bnds(rproc)%uv_swap(bnds(rproc)%rlen2_uv) = swap
         end do
      end do ! n=1,npan

!     Nearest neighbours are defined as those points which send/recv 
!     boundary information.
      neighbour = bnds(:)%rlen2 > 0

#ifdef DEBUG
      print*, "Bounds", myid, "SLEN ", bnds(:)%slen
      print*, "Bounds", myid, "RLEN ", bnds(:)%rlen
      print*, "Bounds", myid, "SLENX", bnds(:)%slenx
      print*, "Bounds", myid, "RLENX", bnds(:)%rlenx
      print*, "Bounds", myid, "SLEN2", bnds(:)%slen2
      print*, "Bounds", myid, "RLEN2", bnds(:)%rlen2
      print*, "Neighbour", myid, neighbour
#endif

!     Now, for each processor send the list of points I want.
!     Send all possible pairs and don't assume anything about the symmetry.
!     For completeness, send zero length messages too.
!     Get the length from the message status
!     Also have to send the swap list

      nreq = 0
      do iproc = 1,nproc-1  !
         sproc = modulo(myid+iproc,nproc)
         if ( bnds(sproc)%rlen_uv > 0 ) then
            ! Send list of requests
            nreq = nreq + 1
            call MPI_ISend( bnds(sproc)%request_list_uv(1), bnds(sproc)%rlen_uv, &
                 MPI_INTEGER, sproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
            nreq = nreq + 1
            ! Use the maximum size in the recv call.
            call MPI_IRecv(  bnds(sproc)%send_list_uv(1),  bnds(sproc)%len, &
                 MPI_INTEGER, sproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
         end if
      end do
      if ( nreq > 0 ) then
         call MPI_Waitall(nreq,ireq,status,ierr)
      end if

!     Now get the actual sizes from the status
      nreq = 0
      do iproc = 1,nproc-1  !
         sproc = modulo(myid+iproc,nproc)
         if ( bnds(sproc)%rlen_uv > 0 ) then
            ! To get recv status, advance nreq by 2
            nreq = nreq + 2
            call MPI_Get_count(status(1,nreq), MPI_INTEGER, count, ierr)
            ! This the number of points I have to send to rproc.
            bnds(sproc)%slen_uv = count
         end if
      end do

      ! Now send the second set
      nreq = 0
      do iproc = 1,nproc-1  !
         sproc = modulo(myid+iproc,nproc)
         if ( bnds(sproc)%rlen_uv > 0 ) then
            ! Send list of requests
            nreq = nreq + 1
            call MPI_ISend( bnds(sproc)%request_list_uv(1), bnds(sproc)%rlen2_uv, &
                 MPI_INTEGER, sproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
            nreq = nreq + 1
            ! Use the maximum size in the recv call.
            call MPI_IRecv( bnds(sproc)%send_list_uv(1), bnds(sproc)%len, &
                 MPI_INTEGER, sproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
         end if
      end do
      if ( nreq > 0 ) then
         call MPI_Waitall(nreq,ireq,status,ierr)
      end if

!     Now get the actual sizes from the status
      nreq = 0
      do iproc = 1,nproc-1  !
         sproc = modulo(myid+iproc,nproc)
         if ( bnds(sproc)%rlen_uv > 0 ) then
            ! To get recv status, advance nreq by 2
            nreq = nreq + 2
            call MPI_Get_count(status(1,nreq), MPI_INTEGER, count, ierr)
            ! This the number of points I have to send to rproc.
            bnds(sproc)%slen2_uv = count
         end if
      end do

      ! Only send the swap list once
      nreq = 0
      do iproc = 1,nproc-1  !
         sproc = modulo(myid+iproc,nproc)
         if ( bnds(sproc)%rlen_uv > 0 ) then
            ! Send list of requests
            nreq = nreq + 1
            call MPI_ISend( bnds(sproc)%uv_swap(1), bnds(sproc)%rlen2_uv, &
                 MPI_LOGICAL, sproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
            nreq = nreq + 1
            ! Use the maximum size in the recv call.
            call MPI_IRecv( bnds(sproc)%send_swap(1), bnds(sproc)%len, &
                 MPI_LOGICAL, sproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
         end if
      end do
      if ( nreq > 0 ) then
         call MPI_Waitall(nreq,ireq,status,ierr)
      end if

!     Indices that are missed above (should be a better way to get these)
      do n=1,npan
         do j=1,jpan
            iwwu(indp(2,j,n)) = iwu(indp(1,j,n))
            ieeu(indp(ipan-1,j,n)) = ieu(indp(ipan,j,n))
         end do
         do i=1,ipan
            issv(indp(i,2,n)) = isv(indp(i,1,n))
            innv(indp(i,jpan-1,n)) = inv(indp(i,jpan,n))
         end do
      end do

#ifdef DEBUG
      print*, "Bounds", myid, "SLEN_UV ", bnds(:)%slen_uv
      print*, "Bounds", myid, "RLEN_UV ", bnds(:)%rlen_uv
      print*, "Bounds", myid, "SLEN2_UV ", bnds(:)%slen2_uv
      print*, "Bounds", myid, "RLEN2_UV ", bnds(:)%rlen2_uv
#endif

!  At the moment send_lists use global indices. Convert these to local.
      do iproc = 1,nproc-1  !
         sproc = modulo(myid+iproc,nproc)  ! Send to
         do iq=1,bnds(sproc)%slen2
            ! send_list(iq) is global point index, i, j, n are local
            call indv_mpi(bnds(sproc)%send_list(iq),i,j,n)
            bnds(sproc)%send_list(iq) = indp(i,j,n)
         end do
         do iq=1,bnds(sproc)%slen2_uv
            ! send_list(iq) is global point index, i, j, n are local
            ! Use abs because sign is used as u/v flag
            call indv_mpi(abs(bnds(sproc)%send_list_uv(iq)),i,j,n)
            bnds(sproc)%send_list_uv(iq) = sign(indp(i,j,n),bnds(sproc)%send_list_uv(iq))
         end do
      end do
      do iq=1,bnds(myid)%rlen2
         call indv_mpi(bnds(myid)%request_list(iq),i,j,n)
         bnds(myid)%request_list(iq) = indp(i,j,n)
      end do
      do iq=1,bnds(myid)%rlen2_uv
         call indv_mpi(abs(bnds(myid)%request_list_uv(iq)),i,j,n)
         bnds(myid)%request_list_uv(iq) = sign(indp(i,j,n),bnds(myid)%request_list_uv(iq))
      end do

!  Final check for values that haven't been set properly
      do n=1,npan
         do j=1,jpan
            do i=1,ipan
               iq = indp(i,j,n)
               call check_set( in(iq), "IN", i, j, n, iq)
               call check_set( is(iq), "IS", i, j, n, iq)
               call check_set( iw(iq), "IW", i, j, n, iq)
               call check_set( ie(iq), "IE", i, j, n, iq)
               call check_set( inn(iq), "INN", i, j, n, iq)
               call check_set( iss(iq), "ISS", i, j, n, iq)
               call check_set( iww(iq), "IWW", i, j, n, iq)
               call check_set( iee(iq), "IEE", i, j, n, iq)
               call check_set( ien(iq), "IEN", i, j, n, iq)
               call check_set( ine(iq), "INE", i, j, n, iq)
               call check_set( ise(iq), "ISE", i, j, n, iq)
               call check_set( iwn(iq), "IWN", i, j, n, iq)
               call check_set( ieu(iq), "IEU", i, j, n, iq)
               call check_set( iwu(iq), "IWU", i, j, n, iq)
               call check_set( inv(iq), "INV", i, j, n, iq)
               call check_set( isv(iq), "ISV", i, j, n, iq)
               call check_set( ieeu(iq), "IEEU", i, j, n, iq)
               call check_set( iwwu(iq), "IWWU", i, j, n, iq)
               call check_set( innv(iq), "INNV", i, j, n, iq)
               call check_set( issv(iq), "ISSV", i, j, n, iq)
            end do
         end do
         call check_set( lwws(n), "LWWS", 1, 1, n, 1)
         call check_set( lws(n),  "LWS",  1, 1, n, 1)
         call check_set( lwss(n), "LWSS", 1, 1, n, 1)
         call check_set( les(n),  "LES",  1, 1, n, 1)
         call check_set( lees(n), "LEES", 1, 1, n, 1)
         call check_set( less(n), "LESS", 1, 1, n, 1)
         call check_set( lwwn(n), "LWWN", 1, 1, n, 1)
         call check_set( lwnn(n), "LWNN", 1, 1, n, 1)
         call check_set( leen(n), "LEEN", 1, 1, n, 1)
         call check_set( lenn(n), "LENN", 1, 1, n, 1)
         call check_set( lsww(n), "LSWW", 1, 1, n, 1)
         call check_set( lsw(n),  "LSW",  1, 1, n, 1)
         call check_set( lssw(n), "LSSW", 1, 1, n, 1)
         call check_set( lsee(n), "LSEE", 1, 1, n, 1)
         call check_set( lsse(n), "LSSE", 1, 1, n, 1)
         call check_set( lnww(n), "LNWW", 1, 1, n, 1)
         call check_set( lnw(n),  "LNW",  1, 1, n, 1)
         call check_set( lnnw(n), "LNNW", 1, 1, n, 1)
         call check_set( lnee(n), "LNEE", 1, 1, n, 1)
         call check_set( lnne(n), "LNNE", 1, 1, n, 1)
      end do

   end subroutine bounds_setup

   subroutine check_set(ind,str,i,j,n,iq)
      integer, intent(in) :: ind,i,j,n,iq
      character(len=*) :: str
      if ( ind == huge(1) ) then
         print*, str, " not set", myid, i, j, n, iq
         call MPI_Abort(MPI_COMM_WORLD)
      end if
   end subroutine check_set

   subroutine bounds2(t, nrows, corner)
      ! Copy the boundary regions
      real, dimension(ifull+iextra), intent(inout) :: t
      integer, intent(in), optional :: nrows
      logical, intent(in), optional :: corner
      integer :: iq
      logical :: double, extra
      integer :: ierr, itag = 0, iproc, rproc, sproc
      integer, dimension(MPI_STATUS_SIZE,2*nproc) :: status
      integer :: send_len, recv_len

      call start_log(bounds_begin)

      double = .false.
      extra = .false.
      if (present(nrows)) then
         if ( nrows == 2 ) then
            double = .true.
         end if
      end if
      ! corner is irrelevant in double case
      if ( .not. double .and. present(corner) ) then
         extra = corner
      end if

!     Set up the buffers to send
      nreq = 0
      do iproc = 1,nproc-1  !
         sproc = modulo(myid+iproc,nproc)  ! Send to
         rproc = modulo(myid-iproc,nproc)  ! Recv from
         if ( double ) then
            recv_len = bnds(rproc)%rlen2
            send_len = bnds(sproc)%slen2
         else if ( extra ) then
            recv_len = bnds(rproc)%rlenx
            send_len = bnds(sproc)%slenx
         else
            recv_len = bnds(rproc)%rlen
            send_len = bnds(sproc)%slen
         end if
         if ( recv_len /= 0 ) then
            nreq = nreq + 1
            call MPI_IRecv( bnds(rproc)%rbuf(1),  bnds(rproc)%len, &
                 MPI_REAL, rproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
         end if
         if ( send_len > 0 ) then
            ! Build up list of points
            do iq=1,send_len
               bnds(sproc)%sbuf(iq) = t(bnds(sproc)%send_list(iq))
            end do
            nreq = nreq + 1
            call MPI_ISend( bnds(sproc)%sbuf(1), send_len, &
                 MPI_REAL, sproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
         end if
      end do

      if ( nreq > 0 ) then
         call start_log(mpiwait_begin)
         call MPI_Waitall(nreq,ireq,status,ierr)
         call end_log(mpiwait_end)
      end if

      do iproc = 1,nproc-1  !
         rproc = modulo(myid-iproc,nproc)  ! Recv from
         if ( double ) then
            recv_len = bnds(rproc)%rlen2
         else if ( extra ) then
            recv_len = bnds(rproc)%rlenx
         else
            recv_len = bnds(rproc)%rlen
         end if
         if ( recv_len > 0 ) then
            do iq=1,recv_len
               ! unpack_list(iq) is index into extended region
               t(ifull+bnds(rproc)%unpack_list(iq)) = bnds(rproc)%rbuf(iq)
            end do
         end if
      end do

      ! Finally see if there are any points on my own processor that need
      ! to be fixed up. This will only be in the case when nproc < npanels.
      if ( double ) then
         recv_len = bnds(myid)%rlen2
      else if ( extra ) then
         recv_len = bnds(myid)%rlenx
      else
         recv_len = bnds(myid)%rlen
      end if
!cdir nodep
      do iq=1,recv_len
         ! request_list is same as send_list in this case
         t(ifull+bnds(myid)%unpack_list(iq)) = t(bnds(myid)%request_list(iq))
      end do

      call end_log(bounds_end)

   end subroutine bounds2

   subroutine bounds3(t, nrows, klim, corner)
      ! Copy the boundary regions. Only this routine requires the extra klim
      ! argument (for helmsol).
      real, dimension(ifull+iextra,kl), intent(inout) :: t
      integer, intent(in), optional :: nrows, klim
      logical, intent(in), optional :: corner
      integer :: iq
      logical :: double, extra
      integer :: ierr, itag = 0, iproc, rproc, sproc
      integer, dimension(MPI_STATUS_SIZE,2*nproc) :: status
      integer :: send_len, recv_len, kx

      call start_log(bounds_begin)

      double = .false.
      if (present(nrows)) then
         if ( nrows == 2 ) then
            double = .true.
         end if
      end if
      ! corner is irrelevant in double case
      if ( .not. double .and. present(corner) ) then
         extra = corner
      end if
      if ( present(klim) ) then
         kx = klim
      else
         kx = kl
      end if

!     Set up the buffers to send
      nreq = 0
      do iproc = 1,nproc-1  !
         sproc = modulo(myid+iproc,nproc)  ! Send to
         rproc = modulo(myid-iproc,nproc)  ! Recv from
         if ( double ) then
            recv_len = bnds(rproc)%rlen2
            send_len = bnds(sproc)%slen2
         else if ( extra ) then
            recv_len = bnds(rproc)%rlenx
            send_len = bnds(sproc)%slenx
         else
            recv_len = bnds(rproc)%rlen
            send_len = bnds(sproc)%slen
         end if
         if ( recv_len /= 0 ) then
            nreq = nreq + 1
            call MPI_IRecv( bnds(rproc)%rbuf(1), bnds(rproc)%len, &
                 MPI_REAL, rproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
         end if
         if ( send_len > 0 ) then
            ! Build up list of points
!cdir nodep
            do iq=1,send_len
               bnds(sproc)%sbuf(1+(iq-1)*kx:iq*kx) = t(bnds(sproc)%send_list(iq),1:kx)
            end do
            nreq = nreq + 1
            call MPI_ISend( bnds(sproc)%sbuf(1), send_len*kx, &
                 MPI_REAL, sproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
         end if
      end do

      if ( nreq > 0 ) then
         call start_log(mpiwait_begin)
         call MPI_Waitall(nreq,ireq,status,ierr)
         call end_log(mpiwait_end)
      end if

      do iproc = 1,nproc-1  !
         rproc = modulo(myid-iproc,nproc)  ! Recv from
         if ( double ) then
            recv_len = bnds(rproc)%rlen2
         else if ( extra ) then
            recv_len = bnds(rproc)%rlenx
         else
            recv_len = bnds(rproc)%rlen
         end if
         if ( recv_len > 0 ) then
!cdir nodep
            do iq=1,recv_len
               ! i, j, n are local
               t(ifull+bnds(rproc)%unpack_list(iq),1:kx) = bnds(rproc)%rbuf(1+(iq-1)*kx:iq*kx)
            end do
         end if
      end do

      ! Finally see if there are any points on my own processor that need
      ! to be fixed up. This will only be in the case when nproc < npanels.
      if ( double ) then
         recv_len = bnds(myid)%rlen2
      else if ( extra ) then
         recv_len = bnds(myid)%rlenx
      else
         recv_len = bnds(myid)%rlen
      end if
!cdir nodep
      do iq=1,recv_len
         ! request_list is same as send_list in this case
         t(ifull+bnds(myid)%unpack_list(iq),:) = t(bnds(myid)%request_list(iq),:)
      end do

      call end_log(bounds_end)

   end subroutine bounds3

   subroutine boundsuv2(u, v, nrows)
      ! Copy the boundary regions of u and v. This doesn't require the
      ! diagonal points like (0,0), but does have to take care of the
      ! direction changes.
      real, dimension(ifull+iextra), intent(inout) :: u, v
      integer, intent(in), optional :: nrows
      integer :: iq
      logical :: double
      integer :: ierr, itag = 0, iproc, rproc, sproc
      integer, dimension(MPI_STATUS_SIZE,2*nproc) :: status
      real :: tmp
      integer :: send_len, recv_len

      call start_log(boundsuv_begin)

      double = .false.
      if (present(nrows)) then
         if ( nrows == 2 ) then
            double = .true.
         end if
      end if

!     Set up the buffers to send
      nreq = 0
      do iproc = 1,nproc-1  !
         sproc = modulo(myid+iproc,nproc)  ! Send to
         rproc = modulo(myid-iproc,nproc)  ! Recv from
         if ( double ) then
            recv_len = bnds(rproc)%rlen2_uv
            send_len = bnds(sproc)%slen2_uv
         else
            recv_len = bnds(rproc)%rlen_uv
            send_len = bnds(sproc)%slen_uv
         end if
         if ( recv_len /= 0 ) then
            nreq = nreq + 1
            call MPI_IRecv( bnds(rproc)%rbuf(1), bnds(rproc)%len, &
                 MPI_REAL, rproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
         end if
         if ( send_len > 0 ) then
            ! Build up list of points
!cdir nodep
            do iq=1,send_len
               ! Use abs because sign is used as u/v flag
               if ( (bnds(sproc)%send_list_uv(iq) > 0) .neqv. &
                     bnds(sproc)%send_swap(iq) ) then
                  bnds(sproc)%sbuf(iq) = u(abs(bnds(sproc)%send_list_uv(iq)))
               else
                  bnds(sproc)%sbuf(iq) = v(abs(bnds(sproc)%send_list_uv(iq)))
               end if
            end do
            nreq = nreq + 1
            call MPI_ISend( bnds(sproc)%sbuf(1), send_len, &
                 MPI_REAL, sproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
         end if
      end do

      if ( nreq > 0 ) then
         call start_log(mpiwait_begin)
         call MPI_Waitall(nreq,ireq,status,ierr)
         call end_log(mpiwait_end)
      end if

      do iproc = 1,nproc-1  !
         rproc = modulo(myid-iproc,nproc)  ! Recv from
         if ( double ) then
            recv_len = bnds(rproc)%rlen2_uv
         else
            recv_len = bnds(rproc)%rlen_uv
         end if
         if ( recv_len > 0 ) then
!cdir nodep
            do iq=1,recv_len
               ! unpack_list(iq) is index into extended region
               if ( bnds(rproc)%unpack_list_uv(iq) > 0 ) then
                  u(ifull+bnds(rproc)%unpack_list_uv(iq)) = bnds(rproc)%rbuf(iq)
               else
                  v(ifull-bnds(rproc)%unpack_list_uv(iq)) = bnds(rproc)%rbuf(iq)
               end if
            end do
         end if
      end do

      ! Finally see if there are any points on my own processor that need
      ! to be fixed up. This will only be in the case when nproc < npanels.
      if ( bnds(myid)%rlen_uv > 0 ) then
         if ( double ) then
            recv_len = bnds(myid)%rlen2_uv
         else
            recv_len = bnds(myid)%rlen_uv
         end if
!cdir nodep
         do iq=1,recv_len
            ! request_list is same as send_list in this case
            if ( ( bnds(myid)%request_list_uv(iq) > 0) .neqv. &
                      bnds(myid)%uv_swap(iq) ) then  ! haven't copied to send_swap yet
               tmp = u(abs(bnds(myid)%request_list_uv(iq)))
            else
               tmp = v(abs(bnds(myid)%request_list_uv(iq)))
            end if
            ! unpack_list(iq) is index into extended region
            if ( bnds(myid)%unpack_list_uv(iq) > 0 ) then
               u(ifull+bnds(myid)%unpack_list_uv(iq)) = tmp
            else
               v(ifull-bnds(myid)%unpack_list_uv(iq)) = tmp
            end if
         end do
      end if

      call end_log(boundsuv_end)

   end subroutine boundsuv2

   subroutine boundsuv3(u, v, nrows)
      ! Copy the boundary regions of u and v. This doesn't require the
      ! diagonal points like (0,0), but does have to take care of the
      ! direction changes.
      real, dimension(ifull+iextra,kl), intent(inout) :: u, v
      integer, intent(in), optional :: nrows
      integer :: iq
      logical :: double
      integer :: ierr, itag = 0, iproc, rproc, sproc
      integer, dimension(MPI_STATUS_SIZE,2*nproc) :: status
      real, dimension(maxbuflen) :: tmp
      integer :: send_len, recv_len

      call start_log(boundsuv_begin)

      double = .false.
      if (present(nrows)) then
         if ( nrows == 2 ) then
            double = .true.
         end if
      end if

!     Set up the buffers to send
      nreq = 0
      do iproc = 1,nproc-1  !
         sproc = modulo(myid+iproc,nproc)  ! Send to
         rproc = modulo(myid-iproc,nproc)  ! Recv from
         if ( double ) then
            recv_len = bnds(rproc)%rlen2_uv
            send_len = bnds(sproc)%slen2_uv
         else
            recv_len = bnds(rproc)%rlen_uv
            send_len = bnds(sproc)%slen_uv
         end if
         if ( recv_len /= 0 ) then
            nreq = nreq + 1
            call MPI_IRecv( bnds(rproc)%rbuf(1), bnds(rproc)%len, &
                 MPI_REAL, rproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
         end if
         if ( send_len > 0 ) then
            ! Build up list of points
!cdir nodep
            do iq=1,send_len
               ! send_list_uv(iq) is point index.
               ! Use abs because sign is used as u/v flag
               if ( (bnds(sproc)%send_list_uv(iq) > 0) .neqv. &
                     bnds(sproc)%send_swap(iq) ) then
                  bnds(sproc)%sbuf(1+(iq-1)*kl:iq*kl) = u(abs(bnds(sproc)%send_list_uv(iq)),:)
               else
                  bnds(sproc)%sbuf(1+(iq-1)*kl:iq*kl) = v(abs(bnds(sproc)%send_list_uv(iq)),:)
               end if 
            end do
            nreq = nreq + 1
            call MPI_ISend( bnds(sproc)%sbuf(1), send_len*kl, &
                 MPI_REAL, sproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
         end if
      end do

      if ( nreq > 0 ) then
         call start_log(mpiwait_begin)
         call MPI_Waitall(nreq,ireq,status,ierr)
         call end_log(mpiwait_end)
      end if

      do iproc = 1,nproc-1  !
         rproc = modulo(myid-iproc,nproc)  ! Recv from
         if ( double ) then
            recv_len = bnds(rproc)%rlen2_uv
         else
            recv_len = bnds(rproc)%rlen_uv
         end if
         if ( recv_len > 0 ) then
!cdir nodep
            do iq=1,recv_len
               ! unpack_list(iq) is index into extended region
               if ( bnds(rproc)%unpack_list_uv(iq) > 0 ) then
                  u(ifull+bnds(rproc)%unpack_list_uv(iq),:) = bnds(rproc)%rbuf(1+(iq-1)*kl:iq*kl)
               else
                  v(ifull-bnds(rproc)%unpack_list_uv(iq),:) = bnds(rproc)%rbuf(1+(iq-1)*kl:iq*kl)
               end if
            end do
         end if
      end do

      ! Finally see if there are any points on my own processor that need
      ! to be fixed up. This will only be in the case when nproc < npanels.
      if ( bnds(myid)%rlen_uv > 0 ) then
         if ( double ) then
            recv_len = bnds(myid)%rlen2_uv
         else
            recv_len = bnds(myid)%rlen_uv
         end if
!!$!cdir nodep
!!$         do iq=1,recv_len
!!$            ! request_list is same as send_list in this case
!!$            if ( (bnds(myid)%request_list_uv(iq) > 0) .neqv. &
!!$                     bnds(myid)%uv_swap(iq) ) then  ! haven't copied to send_swap yet
!!$               tmp = u(abs(bnds(myid)%request_list_uv(iq)),:)
!!$            else
!!$               tmp = v(abs(bnds(myid)%request_list_uv(iq)),:)
!!$            end if
!!$            ! unpack_list(iq) is index into extended region
!!$            if ( bnds(myid)%unpack_list_uv(iq) > 0 ) then
!!$               u(ifull+bnds(myid)%unpack_list_uv(iq),:) = tmp
!!$            else
!!$               v(ifull-bnds(myid)%unpack_list_uv(iq),:) = tmp
!!$            end if
!!$         end do
!        Split this in two for better vectorisation
!cdir nodep
         do iq=1,recv_len
            ! request_list is same as send_list in this case
            if ( (bnds(myid)%request_list_uv(iq) > 0) .neqv. &
                     bnds(myid)%uv_swap(iq) ) then  ! haven't copied to send_swap yet
               tmp(1+(iq-1)*kl:iq*kl) = u(abs(bnds(myid)%request_list_uv(iq)),:)
            else
               tmp(1+(iq-1)*kl:iq*kl) = v(abs(bnds(myid)%request_list_uv(iq)),:)
            end if
         end do
!cdir nodep
         do iq=1,recv_len
            ! unpack_list(iq) is index into extended region
            if ( bnds(myid)%unpack_list_uv(iq) > 0 ) then
               u(ifull+bnds(myid)%unpack_list_uv(iq),:) = tmp(1+(iq-1)*kl:iq*kl)
            else
               v(ifull-bnds(myid)%unpack_list_uv(iq),:) = tmp(1+(iq-1)*kl:iq*kl)
            end if
         end do
      end if

      call end_log(boundsuv_end)

   end subroutine boundsuv3

   subroutine deptsync(nface,xg,yg)
      ! Different levels will have different winds, so the list of points is
      ! different on each level.
      ! xg ranges from 0.5 to il+0.5 on a face. A given processors range
      ! is 0.5+ioff to 0.5+ipan+ioff
      ! Assignment of points to processors needs to match what ints does
      ! in case there's an exact edge point.
      ! Because of the boundary region, the range [0:ipan+1) can be handled.
      ! Need floor(xxg) in range [0:ipan]
      integer, dimension(ifull,kl), intent(in) :: nface
      real, dimension(ifull,kl), intent(in) :: xg, yg
      integer :: iproc
      real, dimension(4,maxsize,0:nproc) :: buf
      integer :: nreq, itag = 99, ierr, rproc, sproc
      integer, dimension(2*nproc) :: ireq
      integer, dimension(MPI_STATUS_SIZE,2*nproc) :: status
      integer :: count, ip, jp
      integer :: iq, k, idel, jdel, nf

      ! This does nothing in the one processor case
      if ( nproc == 1 ) return

      call start_log(deptsync_begin)
      dslen = 0
      drlen = 0
      dindex = 0
      do k=1,kl
         do iq=1,ifull
            nf = nface(iq,k) + noff ! Make this a local index
            idel = int(xg(iq,k)) - ioff
            jdel = int(yg(iq,k)) - joff
            if ( idel < 0 .or. idel > ipan .or. jdel < 0 .or. jdel > jpan &
                 .or. nf < 1 .or. nf > npan ) then
               ! If point is on a different face, add to a list 
               ip = min(il_g,max(1,nint(xg(iq,k))))
               jp = min(il_g,max(1,nint(yg(iq,k))))
               iproc = fproc(ip,jp,nface(iq,k))
! This prevents vectorisation
#ifdef debug
               if ( iproc == myid ) then
                  print*, "Inconsistency in deptsync"
                  call MPI_Abort(MPI_COMM_WORLD,ierr)
               end if
#endif
               ! Add this point to the list of requests I need to send to iproc
               dslen(iproc) = dslen(iproc) + 1
#ifdef debug
               call checksize(dslen(iproc),"Deptssync")
#endif
               ! Since nface is a small integer it can be exactly represented by a
               ! real. It's simpler to send like this than use a proper structure.
               buf(:,dslen(iproc),iproc) = (/ real(nface(iq,k)), xg(iq,k), yg(iq,k), real(k) /)
               dindex(:,dslen(iproc),iproc) = (/ iq,k /)
            end if
         end do
      end do

!     In this case the length of each buffer is unknown and will not
!     be symmetric between processors. Therefore need to get the length
!     from the message status
      nreq = 0
      do iproc = 1,nproc-1  !
         ! Is there any advantage to this ordering here or would send/recv
         ! to the same processor be just as good?
         sproc = modulo(myid+iproc,nproc)  ! Send to
         rproc = modulo(myid-iproc,nproc)  ! Recv from
         if ( neighbour(sproc) ) then
            ! Send, even if length is zero
            nreq = nreq + 1
            call MPI_ISend( buf(1,1,sproc), 4*dslen(sproc), &
                    MPI_REAL, sproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
         else
            if ( dslen(sproc) > 0 ) then
               print*, "Error, dslen > 0 for non neighhour",      &
                    myid, sproc, dslen(sproc)
               stop
            end if
         end if
         if ( neighbour(rproc) ) then
            nreq = nreq + 1
            ! Use the maximum size in the recv call.
            call MPI_IRecv( dpoints(1,1,rproc), 4*maxsize, &
                         MPI_REAL, rproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
         end if
      end do
      if ( nreq > 0 ) then
         call start_log(mpiwait_begin)
         call MPI_Waitall(nreq,ireq,status,ierr)
         call end_log(mpiwait_end)
      end if

!     Now get the actual sizes from the status
      nreq = 0
      do iproc = 1,nproc-1  !
         sproc = modulo(myid+iproc,nproc)  ! Send to
         rproc = modulo(myid-iproc,nproc)  ! Recv from
         if ( neighbour(sproc) ) nreq = nreq + 1 ! Advance because sent to this one
         if ( neighbour(rproc) ) then
            nreq = nreq + 1
            call MPI_Get_count(status(1,nreq), MPI_REAL, count, ierr)
            drlen(rproc) = count/4
         end if
      end do

      call end_log(deptsync_end)
!!!      print*, "DEPTSYNC", myid, drlen, dindex(:,:10,:)

   end subroutine deptsync

   subroutine intssync(s)
      real, dimension(:,:), intent(inout) :: s
      integer :: iproc
      real, dimension(maxsize,0:nproc) :: buf
      integer :: nreq, itag = 0, ierr, rproc, sproc
      integer :: iq
      integer, dimension(2*nproc) :: ireq
      integer, dimension(MPI_STATUS_SIZE,2*nproc) :: status

      call start_log(intssync_begin)

      ! When sending the results, roles of dslen and drlen are reversed
      nreq = 0
      do iproc = 1,nproc-1  !
         sproc = modulo(myid+iproc,nproc)  ! Send to
         rproc = modulo(myid-iproc,nproc)  ! Recv from
         if ( drlen(sproc) /= 0 ) then
            nreq = nreq + 1
            call MPI_ISend( sextra(1,sproc), drlen(sproc), &
                 MPI_REAL, sproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
         end if
         if ( dslen(rproc) /= 0 ) then
            nreq = nreq + 1
            call MPI_IRecv( buf(1,rproc), dslen(rproc), &
                            MPI_REAL, rproc, itag, MPI_COMM_WORLD, ireq(nreq), ierr )
         end if
      end do
      if ( nreq > 0 ) then
         call start_log(mpiwait_begin)
         call MPI_Waitall(nreq,ireq,status,ierr)
         call end_log(mpiwait_end)
      end if

      do iproc=0,nproc-1
         if ( iproc == myid ) then
            cycle
         end if
!!!         print*, "INTSSYNC recvd", myid, buf(1:dslen(iproc),iproc)
         do iq=1,dslen(iproc)
!!!            print*, "UNPACKING", myid, dindex(1,iq,iproc),dindex(2,iq,iproc), buf(iq,iproc) 
            s(dindex(1,iq,iproc),dindex(2,iq,iproc)) = buf(iq,iproc)
         end do
      end do
      call end_log(intssync_end)

   end subroutine intssync

   subroutine indv_mpi(iq, i, j, n)
      integer , intent(in) :: iq
      integer , intent(out) :: i
      integer , intent(out) :: j
      integer , intent(out) :: n

      ! Calculate local i, j, n from global iq

      ! Global i, j, n
      n = (iq - 1)/(il_g*il_g)
      j = 1 + (iq - n*il_g*il_g - 1)/il_g
      i = iq - (j - 1)*il_g - n*il_g*il_g
      if ( fproc(i,j,n) /= myid ) then
         write(*,"(a,5i5)") "Consistency failure in indv_mpi", myid, iq, i, j, n
         call MPI_Abort(MPI_COMM_WORLD)
      end if
      ! Reduced to values on my processor
      n = n + noff
      j = j - joff
      i = i - ioff
   end subroutine indv_mpi

   function indglobal(i,j,n) result(iq)
      integer, intent(in) :: i, j, n
      integer :: iq

      ! Calculate a 1D global index from the global indices
      ! n in range 0:npanels
      iq = i + (j-1)*il_g + n*il_g*il_g
   end function indglobal

   function indg(i,j,n) result(iq)
      integer, intent(in) :: i, j, n
      integer :: iq

      ! Calculate a 1D global index from the local processors indices
      ! n in range 1..npan
      iq = i+ioff + (j+joff-1)*il_g + (n-noff)*il_g*il_g
   end function indg

   function indp(i,j,n) result(iq)
      integer, intent(in) :: i, j, n
      integer :: iq

      ! Calculate a 1D local index from the local processors indices
      ! Note that face number runs from 1 here.
      iq = i + (j-1)*ipan + (n-1)*ipan*jpan
   end function indp

   function iq2iqg(iq) result(iqg)
      integer, intent(in) :: iq
      integer :: iqg
      integer :: i, j, n

      ! Calculate global iqg from local iq

      ! Calculate local i, j, n
      n = 1 + (iq-1) / (il*jl)  ! In range 1 .. npan
      j = 1 + ( iq - (n-1)*(il*jl) - 1) / il
      i = iq - (j-1)*il - (n-1)*(il*jl)
      iqg = indg(i,j,n)

   end function iq2iqg

   subroutine checksize(len, mesg)
      integer, intent(in) :: len
      character(len=*), intent(in) :: mesg
      integer :: ierr
      if ( len > maxsize ) then
         print*, "Error, maxsize exceeded in ", mesg
         call MPI_Abort(MPI_COMM_WORLD,ierr)
      end if
   end subroutine checksize

   subroutine check_bnds_alloc(rproc, iext)
      integer, intent(in) :: rproc
      integer, intent(in) :: iext
      integer :: len, ierr

!     Allocate the components of the bnds array. It's too much work to
!     get the exact sizes, so allocate a fixed size for each case where
!     there's an interaction.
      if ( bnds(rproc)%len == 0 ) then
         ! Not allocated yet.
         len = maxbuflen
         allocate ( bnds(rproc)%rbuf(len) )
         allocate ( bnds(rproc)%sbuf(len) )
         allocate ( bnds(rproc)%request_list(len) )
         allocate ( bnds(rproc)%send_list(len) )
         allocate ( bnds(rproc)%unpack_list(len) )
         allocate ( bnds(rproc)%request_list_uv(len) )
         allocate ( bnds(rproc)%send_list_uv(len) )
         allocate ( bnds(rproc)%unpack_list_uv(len) )
         allocate ( bnds(rproc)%uv_swap(len), bnds(rproc)%send_swap(len) )
         bnds(rproc)%len = len
      else
         ! Just check length
         if ( kl*bnds(rproc)%rlen >=  bnds(rproc)%len ) then
            print*, "Error, maximum length error in check_bnds_alloc"
            print*, myid, rproc, bnds(rproc)%rlen,  bnds(rproc)%len, kl
            call MPI_Abort(MPI_COMM_WORLD,ierr)
         end if
         if ( iext >= iextra ) then
            print*, "Error, iext maximum length error in check_bnds_alloc"
            print*, myid, iext, iextra
            call MPI_Abort(MPI_COMM_WORLD,ierr)
         end if
      end if
   end subroutine check_bnds_alloc

   subroutine fix_index(iqx,larray,n,bnds,iext)
      integer, intent(in) :: iqx, n
      integer, dimension(:), intent(out) :: larray
      integer, intent(inout) :: iext
      type(bounds_info), dimension(0:), intent(inout) :: bnds
      integer :: rproc, iloc,jloc,nloc

      ! This processes extra corner points, so adds to rlenx
      ! Which processor has this point
      rproc = qproc(iqx)
      if ( rproc /= myid ) then ! Add to list
         call check_bnds_alloc(rproc, iext)
         bnds(rproc)%rlenx = bnds(rproc)%rlenx + 1
         bnds(rproc)%request_list(bnds(rproc)%rlenx) = iqx
         ! Increment extended region index
         iext = iext + 1
         bnds(rproc)%unpack_list(bnds(rproc)%rlenx) = iext
         larray(n) = ifull+iext
      else
         ! If it's on this processor, just use the local index
         call indv_mpi(iqx,iloc,jloc,nloc)
         larray(n) = indp(iloc,jloc,nloc)
      end if
   end subroutine fix_index

   subroutine fix_index2(iqx,larray,n,bnds,iext)
      integer, intent(in) :: iqx, n
      integer, dimension(:), intent(out) :: larray
      integer, intent(inout) :: iext
      type(bounds_info), dimension(0:), intent(inout) :: bnds
      integer :: rproc, iloc,jloc,nloc

      ! Which processor has this point
      rproc = qproc(iqx)
      if ( rproc /= myid ) then ! Add to list
         call check_bnds_alloc(rproc, iext)
         bnds(rproc)%rlen2 = bnds(rproc)%rlen2 + 1
         bnds(rproc)%request_list(bnds(rproc)%rlen2) = iqx
         ! Increment extended region index
         iext = iext + 1
         bnds(rproc)%unpack_list(bnds(rproc)%rlen2) = iext
         larray(n) = ifull+iext
      else
         ! If it's on this processor, just use the local index
         call indv_mpi(iqx,iloc,jloc,nloc)
         larray(n) = indp(iloc,jloc,nloc)
      end if
   end subroutine fix_index2

   subroutine proc_setup(npanels,ifull)
      include 'parm.h'
!     Routine to set up offsets etc.
      integer, intent(in) :: npanels, ifull
      integer :: i, j, n, ierr, iproc, nd, jdf, idjd_g

      !  Processor allocation
      !  if  nproc <= npanels+1, then each gets a number of full panels
      if ( nproc <= npanels+1 ) then
         if ( modulo(npanels+1,nproc) /= 0 ) then
            print*, "Error, number of processors must divide number of panels"
            call MPI_Abort(MPI_COMM_WORLD,ierr)
         end if
!         npan = (npanels+1)/nproc
         ipan = il_g
         jpan = il_g
         noff = 1 - myid*npan
         ioff = 0
         joff = 0
         do n=0,npanels
            fproc(:,:,n) = n/npan
            qproc(1+n*il_g**2:(n+1)*il_g**2) = n/npan
         end do
      else  ! nproc >= npanels+1
         if ( modulo (nproc, npanels+1) /= 0 ) then
            print*, "Error, number of processors must be a multiple of number of panels"
            call MPI_Abort(MPI_COMM_WORLD,ierr)
         end if
!         npan = 1
         n = nproc / (npanels+1)
         !  n is the number of processors on each face
         !  Try to factor this into two values are close as possible.
         !  nxproc is the smaller of the 2.
         nxproc = nint(sqrt(real(n)))
         do nxproc = nint(sqrt(real(n))), 1, -1
            ! This will always exit because it's trivially true for nxproc=1
            if ( modulo(n,nxproc) == 0 ) exit
         end do
         nyproc = n / nxproc
         if ( myid == 0 ) then
            print*, "NXPROC, NYPROC", nxproc, nyproc
         end if
         if ( nxproc*nyproc /= n ) then
            print*, "Error in splitting up faces"
            call MPI_Abort(MPI_COMM_WORLD,ierr)
         end if

         ! Still need to check that the processor distribution is compatible
         ! with the grid.
         if ( modulo(il_g,nxproc) /= 0 ) then
            print*, "Error, il not a multiple of nxproc", il_g, nxproc
            call MPI_Abort(MPI_COMM_WORLD,ierr)
         end if
         if ( modulo(il_g,nyproc) /= 0 ) then
            print*, "Error, il not a multiple of nyproc", il_g, nyproc
            call MPI_Abort(MPI_COMM_WORLD,ierr)
         end if
         ipan = il_g/nxproc
         jpan = il_g/nyproc

         iproc = 0
         qproc = -9999 ! Mask value so any points not set are obvious.
         do n=0,npanels
            do j=1,il_g,jpan
               do i=1,il_g,ipan
                  fproc(i:i+ipan-1,j:j+jpan-1,n) = iproc
                  iproc = iproc + 1
               end do
            end do
         end do

         do n=0,npanels
            do j=1,il_g
               do i=1,il_g
                  qproc(indglobal(i,j,n)) = fproc(i,j,n)
               end do
            end do
         end do

         ! Set offsets for this processor
         call proc_region(myid,ioff,joff,noff)
      end if

!     Check that the values calculated here match those set as parameters
      if ( ipan /= il ) then
         print*, "Error, parameter mismatch, ipan /= il", ipan, il
         call MPI_Abort(MPI_COMM_WORLD,ierr)
      end if
      if ( jpan*npan /= jl ) then
         print*, "Error, parameter mismatch, jpan*npan /= jl", jpan, npan, jl
         call MPI_Abort(MPI_COMM_WORLD,ierr)
      end if

!      ipfull = ipan*jpan*npan
!      iextra = 4*npan*(ipan+jpan+8)
!      print*, "ipfull, iextra", ipfull, iextra

      ! Convert standard jd to a face index
      nd = (jd-1)/il_g ! 0: to match fproc
      jdf = jd - nd*il_g
      mydiag = ( myid == fproc(id,jdf,nd) )
      ! Convert global indices to ones on this processors region
      idjd_g = id + (jd-1)*il_g
      if ( mydiag ) then
         call indv_mpi(idjd_g,i,j,n)
         idjd = indp(i,j,n)
      else
         ! This should never be used so set a value that will give a bounds error
         idjd = huge(1)
      end if

   end subroutine proc_setup

   subroutine proc_setup_uniform(npanels,ifull)
      include 'parm.h'
!     Routine to set up offsets etc for the uniform decomposition
      integer, intent(in) :: npanels, ifull
      integer :: i, j, n, ierr, iproc, nd, jdf, idjd_g

      if ( npan /= npanels+1 ) then
         print*, "Error: inconsistency in proc_setup_uniform"
         print*, "Check that correct version of newmpar.h was used"
         stop
      end if
      !  Processor allocation: each processor gets a part of each panel
      !  Try to factor nproc into two values are close as possible.
      !  nxproc is the smaller of the 2.
      nxproc = nint(sqrt(real(nproc)))
      do nxproc = nint(sqrt(real(nproc))), 1, -1
         ! This will always exit eventually because it's trivially true 
         ! for nxproc=1
         if ( modulo(nproc,nxproc) == 0 ) exit
      end do
      nyproc = nproc / nxproc
      if ( myid == 0 ) then
         print*, "NXPROC, NYPROC", nxproc, nyproc, iextra
      end if
      if ( nxproc*nyproc /= nproc ) then
         print*, "Error in splitting up faces"
         call MPI_Abort(MPI_COMM_WORLD,ierr)
      end if

      ! Still need to check that the processor distribution is compatible
      ! with the grid.
      if ( modulo(il_g,nxproc) /= 0 ) then
         print*, "Error, il not a multiple of nxproc", il_g, nxproc
         call MPI_Abort(MPI_COMM_WORLD,ierr)
      end if
      if ( modulo(il_g,nyproc) /= 0 ) then
         print*, "Error, il not a multiple of nyproc", il_g, nyproc
         call MPI_Abort(MPI_COMM_WORLD,ierr)
      end if
      ipan = il_g/nxproc
      jpan = il_g/nyproc

      iproc = 0
      qproc = -9999 ! Mask value so any points not set are obvious.
      do j=1,il_g,jpan
         do i=1,il_g,ipan
            fproc(i:i+ipan-1,j:j+jpan-1,:) = iproc
            iproc = iproc + 1
         end do
      end do

      do n=0,npanels
         do j=1,il_g
            do i=1,il_g
               qproc(indglobal(i,j,n)) = fproc(i,j,n)
            end do
         end do
      end do

      ! Set offsets for this processor
      call proc_region(myid,ioff,joff,noff)

!     Check that the values calculated here match those set as parameters
      if ( ipan /= il ) then
         print*, "Error, parameter mismatch, ipan /= il", ipan, il
         call MPI_Abort(MPI_COMM_WORLD,ierr)
      end if
      if ( jpan*npan /= jl ) then
         print*, "Error, parameter mismatch, jpan*npan /= jl", jpan, npan, jl
         call MPI_Abort(MPI_COMM_WORLD,ierr)
      end if

!      ipfull = ipan*jpan*npan
!      iextra = 4*npan*(ipan+jpan+8)
!      print*, "ipfull, iextra", ipfull, iextra

      ! Convert standard jd to a face index
      nd = (jd-1)/il_g ! 0: to match fproc
      jdf = jd - nd*il_g
      mydiag = ( myid == fproc(id,jdf,nd) )
      ! Convert global indices to ones on this processors region
      idjd_g = id + (jd-1)*il_g
      if ( mydiag ) then
         call indv_mpi(idjd_g,i,j,n)
         idjd = indp(i,j,n)
      else
         ! This should never be used so set a value that will give a bounds error
         idjd = huge(1)
      end if

   end subroutine proc_setup_uniform

   subroutine proc_region(procid,ipoff,jpoff,npoff)
      ! Calculate the offsets for a given processor
      integer, intent(in) :: procid
      integer, intent(out) :: ipoff, jpoff, npoff
      integer :: myface, mtmp

#ifdef uniform_decomp
      ! Set offsets for this processor (same on all faces)
      npoff = 1
      jpoff = (procid/nxproc) * jpan
      ipoff = modulo(procid,nxproc)*ipan
#else
      if ( nproc <= npanels+1 ) then
         npoff = 1 - procid*npan
         ipoff = 0
         jpoff = 0
      else
         myface = procid / (nxproc*nyproc)
         npoff = 1 - myface
         ! mtmp is the processor index on this face, 0:(nxprox*nyproc-1)
         mtmp = procid - myface*(nxproc*nyproc)
         jpoff = (mtmp/nxproc) * jpan
         ipoff = modulo(mtmp,nxproc)*ipan
      end if
#endif
   end subroutine proc_region

   subroutine start_log ( event )
      integer, intent(in) :: event
      integer :: ierr
#ifdef vampir
      include "VT.inc"
#endif
#ifdef mpilog
      ierr = MPE_log_event(event,0,"")
#endif
#ifdef vampir
      call vtenter(event, VT_NOSCL, ierr)
#endif
#ifdef simple_timer
#ifdef scyld
      double precision :: MPI_Wtime
#endif
      start_time(event) = MPI_Wtime()
#endif 
   end subroutine start_log

   subroutine end_log ( event )
      integer, intent(in) :: event
      integer :: ierr
#ifdef vampir
      include "VT.inc"
#endif
#ifdef mpilog
      ierr = MPE_log_event(event,0,"")
#endif
#ifdef vampir
      call vtleave(VT_NOSCL, ierr)
#endif
#ifdef simple_timer
#ifdef scyld
      double precision :: MPI_Wtime
#endif
      tot_time(event) = tot_time(event) + MPI_Wtime() - start_time(event)
#endif 
   end subroutine end_log

   subroutine log_off()
#ifdef vampir
      call vttraceoff()
#endif
   end subroutine log_off
   
   subroutine log_on()
#ifdef vampir
      call vttraceon()
#endif
   end subroutine log_on

   subroutine log_setup()
      integer :: ierr
      integer :: classhandle
#ifdef mpilog
      bounds_begin = MPE_Log_get_event_number()
      bounds_end = MPE_Log_get_event_number()
      ierr = MPE_Describe_state(bounds_begin, bounds_end, "Bounds", "yellow")
      boundsa_begin = MPE_Log_get_event_number()
      boundsa_end = MPE_Log_get_event_number()
      ierr = MPE_Describe_state(boundsa_begin, boundsa_end, "BoundsA", "DarkOrange1")
      boundsb_begin = MPE_Log_get_event_number()
      boundsb_end = MPE_Log_get_event_number()
      ierr = MPE_Describe_state(boundsb_begin, boundsb_end, "BoundsB", "DarkOrange1")
      boundsuv_begin = MPE_Log_get_event_number()
      boundsuv_end = MPE_Log_get_event_number()
      ierr = MPE_Describe_state(boundsuv_begin, boundsuv_end, "BoundsUV", "khaki")
      ints_begin = MPE_Log_get_event_number()
      ints_end = MPE_Log_get_event_number()
      ierr = MPE_Describe_state(ints_begin, ints_end, "Ints","goldenrod")
      nonlin_begin = MPE_Log_get_event_number()
      nonlin_end = MPE_Log_get_event_number()
      ierr = MPE_Describe_state(nonlin_begin, nonlin_end, "Nonlin", "IndianRed")
      helm_begin = MPE_Log_get_event_number()
      helm_end = MPE_Log_get_event_number()
      ierr = MPE_Describe_state(helm_begin, helm_end, "Helm", "magenta1")
      adjust_begin = MPE_Log_get_event_number()
      adjust_end = MPE_Log_get_event_number()
      ierr = MPE_Describe_state(adjust_begin, adjust_end, "Adjust", "blue")
      upglobal_begin = MPE_Log_get_event_number()
      upglobal_end = MPE_Log_get_event_number()
      ierr = MPE_Describe_state(upglobal_begin, upglobal_end, "Upglobal", "ForestGreen")
      depts_begin = MPE_Log_get_event_number()
      depts_end = MPE_Log_get_event_number()
      ierr = MPE_Describe_state(depts_begin, depts_end, "Depts", "pink1")
      deptsync_begin = MPE_Log_get_event_number()
      deptsync_end = MPE_Log_get_event_number()
      ierr = MPE_Describe_state(deptsync_begin, deptsync_end, "Deptsync", "YellowGreen")
      intssync_begin = MPE_Log_get_event_number()
      intssync_end = MPE_Log_get_event_number()
      ierr = MPE_Describe_state(intssync_begin, intssync_end, "Intssync", "YellowGreen")
      stag_begin = MPE_Log_get_event_number()
      stag_end = MPE_Log_get_event_number()
      ierr = MPE_Describe_state(stag_begin, stag_end, "Stag", "YellowGreen")
      toij_begin = MPE_Log_get_event_number()
      toij_end = MPE_Log_get_event_number()
      ierr = MPE_Describe_state(toij_begin, toij_end, "Toij", "blue")
      physloadbal_begin = MPE_Log_get_event_number()
      physloadbal_end = MPE_Log_get_event_number()
      ierr = MPE_Describe_state(physloadbal_begin, physloadbal_end, "PhysLBbal", "blue")
      phys_begin = MPE_Log_get_event_number()
      phys_end = MPE_Log_get_event_number()
      ierr = MPE_Describe_state(phys_begin, phys_end, "Phys", "Yellow")
      outfile_begin = MPE_Log_get_event_number()
      outfile_end = MPE_Log_get_event_number()
      ierr = MPE_Describe_state(outfile_begin, outfile_end, "Outfile", "Yellow")
      indata_begin = MPE_Log_get_event_number()
      indata_end = MPE_Log_get_event_number()
      ierr = MPE_Describe_state(indata_begin, indata_end, "Indata", "Yellow")
#endif
#ifdef vampir
      call vtfuncdef("Bounds", classhandle, bounds_begin, ierr)
      bounds_end = bounds_begin
      call vtfuncdef("BoundsA", classhandle, boundsa_begin, ierr)
      boundsa_end = boundsa_end
      call vtfuncdef("BoundsB", classhandle, boundsb_begin, ierr)
      boundsb_end = boundsb_begin
      call vtfuncdef("BoundsUV", classhandle, boundsuv_begin, ierr)
      boundsuv_end = boundsuv_begin
      call vtfuncdef("Ints", classhandle, ints_begin, ierr)
      ints_end = ints_begin 
      call vtfuncdef("Nonlin", classhandle, nonlin_begin, ierr)
      nonlin_end = nonlin_begin 
      call vtfuncdef("Helm", classhandle, helm_begin, ierr)
      helm_end = helm_begin
      call vtfuncdef("Adjust", classhandle, adjust_begin, ierr)
      adjust_end = adjust_begin
      call vtfuncdef("Upglobal", classhandle, upglobal_begin, ierr)
      upglobal_end = upglobal_begin
      call vtfuncdef("Depts", classhandle, depts_begin, ierr)
      depts_end = depts_begin
      call vtfuncdef("Deptsync", classhandle, deptsync_begin, ierr)
      deptsync_end = deptsync_begin
      call vtfuncdef("Intssync", classhandle, intssync_begin, ierr)
      intssync_end = intssync_begin
      call vtfuncdef("Stag", classhandle, stag_begin, ierr)
      stag_end = stag_begin
      call vtfuncdef("Toij", classhandle, toij_begin, ierr)
      toij_end =  toij_begin
      call vtfuncdef("PhysLBal", classhandle, physloadbal_begin, ierr)
      physloadbal_end =  physloadbal_begin
      call vtfuncdef("Phys", classhandle, phys_begin, ierr)
      phys_end =  physloadbal_begin
      call vtfuncdef("Outfile", classhandle, outfile_begin, ierr)
      outfile_end =  outfile_begin
      call vtfuncdef("Indata", classhandle, indata_begin, ierr)
      indata_end =  indata_begin
#endif
#ifdef simple_timer

      model_begin = 1
      model_end =  model_begin
      event_name(model_begin) = "Whole Model"

      maincalc_begin = 2
      maincalc_end =  maincalc_begin
      event_name(maincalc_begin) = "Main Calc loop"

      phys_begin = 3
      phys_end =  phys_begin
      event_name(phys_begin) = "Phys"

      physloadbal_begin = 4
      physloadbal_end =  physloadbal_begin
      event_name(physloadbal_begin) = "Phys Load Bal"

      ints_begin = 5
      ints_end = ints_begin 
      event_name(ints_begin) = "Ints"

      nonlin_begin = 6
      nonlin_end = nonlin_begin 
      event_name(nonlin_begin) = "Nonlin"

      helm_begin = 7
      helm_end = helm_begin
      event_name(helm_begin) = "Helm"

      adjust_begin = 8
      adjust_end = adjust_begin
      event_name(Adjust_begin) = "Adjust"

      upglobal_begin = 9
      upglobal_end = upglobal_begin
      event_name(upglobal_begin) = "Upglobal"

      depts_begin = 10
      depts_end = depts_begin
      event_name(depts_begin) = "Depts"

      stag_begin = 11
      stag_end = stag_begin
      event_name(stag_begin) = "Stag"

      toij_begin = 12
      toij_end =  toij_begin
      event_name(toij_begin) = "Toij"

      outfile_begin = 13
      outfile_end =  outfile_begin
      event_name(outfile_begin) = "Outfile"

      bounds_begin = 14
      bounds_end = bounds_begin
      event_name(bounds_begin) = "Bounds"

      boundsa_begin = 15
      boundsa_end = boundsa_end
      event_name(boundsa_begin) = "BoundsA"

      boundsb_begin = 16
      boundsb_end = boundsb_begin
      event_name(boundsb_begin) = "BoundsB"

      boundsuv_begin = 17
      boundsuv_end = boundsuv_begin
      event_name(boundsuv_begin) = "BoundsUV"

      deptsync_begin = 18
      deptsync_end = deptsync_begin
      event_name(deptsync_begin) = "Deptsync"

      intssync_begin = 19
      intssync_end = intssync_begin
      event_name(intssync_begin) = "Intssync"

      gather_begin = 20
      gather_end = gather_begin
      event_name(gather_begin) = "Gather"

      distribute_begin = 21
      distribute_end = distribute_begin
      event_name(distribute_begin) = "Distribute"

      reduce_begin = 22
      reduce_end = reduce_begin
      event_name(reduce_begin) = "Reduce"

      precon_begin = 23
      precon_end = precon_begin
      event_name(precon_begin) = "Precon"

      mpiwait_begin = 24
      mpiwait_end = mpiwait_begin
      event_name(mpiwait_begin) = "MPI_Wait"

      indata_begin = 25
      indata_end =  indata_begin
      event_name(indata_begin) = "Indata"

#endif
   end subroutine log_setup
   

   subroutine check_dims
!    Check that the dimensions defined in the newmpar and newmpar_gx file
!    match. A single routine can't include both of these because declarations
!    would conflict so return them from separate functions
      integer :: ierr
      if ( .not. all(get_dims()==get_dims_gx()) ) then
         print*, "Error, mismatch in newmpar.h and newmpar_gx.h"
         call MPI_Abort(MPI_COMM_WORLD,ierr)
      end if

   end subroutine check_dims
   
   function get_dims() result(dims)
      include 'newmpar.h'
      integer, dimension(2) :: dims
      dims = (/ il_g, kl /)
   end function get_dims

   function get_dims_gx() result(dims)
      include 'newmpar_gx.h'
      integer, dimension(2) :: dims
      dims = (/ il, kl /)
   end function get_dims_gx

   subroutine phys_loadbal()
!     This forces a sychronisation to make the physics load imbalance overhead
!     explicit. 
      integer :: ierr
      call start_log(physloadbal_begin)
      call MPI_Barrier( MPI_COMM_WORLD, ierr )
      call end_log(physloadbal_end)
   end subroutine phys_loadbal

#ifdef simple_timer
      subroutine simple_timer_finalize()
         ! Calculate the mean, min and max times for each case
         integer :: i, ierr
         double precision, dimension(nevents) :: emean, emax, emin
         call MPI_Reduce(tot_time, emean, nevents, MPI_DOUBLE_PRECISION, &
                         MPI_SUM, 0, MPI_COMM_WORLD, ierr )
         call MPI_Reduce(tot_time, emax, nevents, MPI_DOUBLE_PRECISION, &
                         MPI_MAX, 0, MPI_COMM_WORLD, ierr )
         call MPI_Reduce(tot_time, emin, nevents, MPI_DOUBLE_PRECISION, &
                         MPI_MIN, 0, MPI_COMM_WORLD, ierr )
         if ( myid == 0 ) then
            print*, "==============================================="
            print*, "  Times over all processes"
            print*, "  Routine        Mean time  Min time  Max time"
            do i=1,nevents
               if ( emean(i) > 0. ) then
                  ! This stops boundsa, b getting written when they're not used.
                  write(*,"(a,3f10.3)") event_name(i), emean(i)/nproc, emin(i), emax(i)
               end if
            end do
         end if
      end subroutine simple_timer_finalize
#endif

    subroutine ccglobal_posneg2 (array, delpos, delneg)
       ! Calculate global sums of positive and negative values of array
       use sumdd_m
       include 'newmpar.h'
       include 'xyzinfo.h'
       real, intent(in), dimension(ifull) :: array
       real, intent(out) :: delpos, delneg
       real :: delpos_l, delneg_l
       real, dimension(2) :: delarr, delarr_l
       integer :: iq, ierr
#ifdef sumdd
       complex, dimension(2) :: local_sum, global_sum
!      Temporary array for the drpdr_local function
       real, dimension(ifull) :: tmparr, tmparr2 
#endif

       delpos_l = 0.
       delneg_l = 0.
       do iq=1,ifull
#ifdef sumdd         
          tmparr(iq)  = max(0.,array(iq)*wts(iq))
          tmparr2(iq) = min(0.,array(iq)*wts(iq))
#else
          delpos_l = delpos_l + max(0.,array(iq)*wts(iq))
          delneg_l = delneg_l + min(0.,array(iq)*wts(iq))
#endif
       enddo
#ifdef sumdd
       local_sum = (0.,0.)
       call drpdr_local(tmparr, local_sum(1))
       call drpdr_local(tmparr2, local_sum(2))
       call MPI_Allreduce ( local_sum, global_sum, 2, MPI_COMPLEX,     &
                            MPI_SUMDR, MPI_COMM_WORLD, ierr )
       delpos = real(global_sum(1))
       delneg = real(global_sum(2))
#else
       delarr_l(1:2) = (/ delpos_l, delneg_l /)
       call MPI_Allreduce ( delarr_l, delarr, 2, MPI_REAL, MPI_SUM,    &
                            MPI_COMM_WORLD, ierr )
       delpos = delarr(1)
       delneg = delarr(2)
#endif

    end subroutine ccglobal_posneg2
    
    subroutine ccglobal_posneg3 (array, delpos, delneg)
       ! Calculate global sums of positive and negative values of array
       use sumdd_m
       include 'newmpar.h'
       include 'sigs.h'
       include 'xyzinfo.h'
       real, intent(in), dimension(ifull,kl) :: array
       real, intent(out) :: delpos, delneg
       real :: delpos_l, delneg_l
       real, dimension(2) :: delarr, delarr_l
       integer :: k, iq, ierr
#ifdef sumdd
       complex, dimension(2) :: local_sum, global_sum
!      Temporary array for the drpdr_local function
       real, dimension(ifull) :: tmparr, tmparr2 
#endif

       delpos_l = 0.
       delneg_l = 0.
#ifdef sumdd         
       local_sum = (0.,0.)
#endif
       do k=1,kl
          do iq=1,ifull
#ifdef sumdd         
             tmparr(iq)  = max(0.,-dsig(k)*array(iq,k)*wts(iq))
             tmparr2(iq) = min(0.,-dsig(k)*array(iq,k)*wts(iq))
#else
             delpos_l = delpos_l + max(0.,-dsig(k)*array(iq,k)*wts(iq))
             delneg_l = delneg_l + min(0.,-dsig(k)*array(iq,k)*wts(iq))
#endif
          end do
#ifdef sumdd
          call drpdr_local(tmparr, local_sum(1))
          call drpdr_local(tmparr2, local_sum(2))
#endif
       end do ! k loop
#ifdef sumdd
       call MPI_Allreduce ( local_sum, global_sum, 2, MPI_COMPLEX,     &
                            MPI_SUMDR, MPI_COMM_WORLD, ierr )
       delpos = real(global_sum(1))
       delneg = real(global_sum(2))
#else
       delarr_l(1:2) = (/ delpos_l, delneg_l /)
       call MPI_Allreduce ( delarr_l, delarr, 2, MPI_REAL, MPI_SUM,    &
                            MPI_COMM_WORLD, ierr )
       delpos = delarr(1)
       delneg = delarr(2)
#endif

    end subroutine ccglobal_posneg3

    subroutine ccglobal_sum2 (array, result)
       ! Calculate global sum of an array
       use sumdd_m
       include 'newmpar.h'
       include 'xyzinfo.h'
       real, intent(in), dimension(ifull) :: array
       real, intent(out) :: result
       real :: result_l
       integer :: iq, ierr
#ifdef sumdd
       complex :: local_sum, global_sum
!      Temporary array for the drpdr_local function
       real, dimension(ifull) :: tmparr
#endif

       result_l = 0.
       do iq=1,ifull
#ifdef sumdd         
          tmparr(iq)  = array(iq)*wts(iq)
#else
          result_l = result_l + array(iq)*wts(iq)
#endif
       enddo
#ifdef sumdd
       local_sum = (0.,0.)
       call drpdr_local(tmparr, local_sum)
       call MPI_Allreduce ( local_sum, global_sum, 1, MPI_COMPLEX,     &
                            MPI_SUMDR, MPI_COMM_WORLD, ierr )
       result = real(global_sum)
#else
       call MPI_Allreduce ( result_l, result, 1, MPI_REAL, MPI_SUM,    &
                            MPI_COMM_WORLD, ierr )
#endif

    end subroutine ccglobal_sum2

    subroutine ccglobal_sum3 (array, result)
       ! Calculate global sum of 3D array, appyling vertical weighting
       use sumdd_m
       include 'newmpar.h'
       include 'sigs.h'
       include 'xyzinfo.h'
       real, intent(in), dimension(ifull,kl) :: array
       real, intent(out) :: result
       real :: result_l
       integer :: k, iq, ierr
#ifdef sumdd
       complex :: local_sum, global_sum
!      Temporary array for the drpdr_local function
       real, dimension(ifull) :: tmparr
#endif

       result_l = 0.
#ifdef sumdd
       local_sum = (0.,0.)
#endif
       do k=1,kl
          do iq=1,ifull
#ifdef sumdd         
             tmparr(iq)  = -dsig(k)*array(iq,k)*wts(iq)
#else
             result_l = result_l - dsig(k)*array(iq,k)*wts(iq)
#endif
          enddo
#ifdef sumdd
          call drpdr_local(tmparr, local_sum)
#endif
       end do ! k

#ifdef sumdd
       call MPI_Allreduce ( local_sum, global_sum, 1, MPI_COMPLEX,    &
                            MPI_SUMDR, MPI_COMM_WORLD, ierr )
       result = real(global_sum)
#else
       call MPI_Allreduce ( result_l, result, 1, MPI_REAL, MPI_SUM,   &
                            MPI_COMM_WORLD, ierr )
#endif

    end subroutine ccglobal_sum3

    ! Read and distribute a global variable
    ! Optional arguments for format and to skip over records
    subroutine readglobvar2(un,var,skip,fmt)
      include 'newmpar.h'
      integer, intent(in) :: un
      real, dimension(:), intent(out) :: var
      logical, intent(in), optional :: skip
      character(len=*), intent(in), optional :: fmt
      real, dimension(ifull_g) :: varg
      logical :: doskip

      doskip = .false.
      if ( present(skip) ) doskip = skip

      if ( doskip ) then
         if ( myid == 0 ) then
            read(un)
         end if
      else
         if ( myid == 0 ) then
            if ( present(fmt) ) then
               if ( fmt == "*" ) then
                  read(un,*) varg
               else
                  read(un,fmt) varg
               end if
            else
               read(un) varg
            end if
            ! Use explicit ranges here because some arguments might be extended.
            call ccmpi_distribute(var(1:ifull),varg)
         else
            call ccmpi_distribute(var(1:ifull))
         end if
      end if

   end subroutine readglobvar2

   subroutine readglobvar2i(un,var,skip,fmt)
      include 'newmpar.h'
      integer, intent(in) :: un
      integer, dimension(:), intent(out) :: var
      logical, intent(in), optional :: skip
      character(len=*), intent(in), optional :: fmt
      integer, dimension(ifull_g) :: varg
      logical :: doskip

      doskip = .false.
      if ( present(skip) ) doskip = skip

      if ( doskip ) then
         if ( myid == 0 ) then
            read(un)
         end if
      else
         if ( myid == 0 ) then
            if ( present(fmt) ) then
               if ( fmt == "*" ) then
                  read(un,*) varg
               else
                  read(un,fmt) varg
               end if
            else
               read(un) varg
            end if
            ! Use explicit ranges here because some arguments might be extended.
            call ccmpi_distribute(var(1:ifull),varg)
         else
            call ccmpi_distribute(var(1:ifull))
         end if
      end if

   end subroutine readglobvar2i

   subroutine readglobvar3(un,var,skip,fmt)
      include 'newmpar.h'
      integer, intent(in) :: un
      real, dimension(:,:), intent(out) :: var
      logical, intent(in), optional :: skip
      real, dimension(ifull_g,size(var,2)) :: varg
      character(len=*), intent(in), optional :: fmt
      integer :: k, kk
      logical :: doskip

      doskip = .false.
      if ( present(skip) ) doskip = skip

      kk = size(var,2)

      if ( doskip ) then
         if ( myid == 0 ) then
            read(un)
         end if
      else
         if ( myid == 0 ) then
            if ( present(fmt) ) then
               if ( fmt == "*" ) then
                  read(un,*) varg
               else
                  read(un,fmt) varg
               end if
            else
               read(un) varg
            end if
            ! Use explicit ranges here because some arguments might be extended.
            ! ccmpi_distribute3 expects kl, it's not general
            if ( kk == kl ) then
               call ccmpi_distribute(var(1:ifull,:),varg)
            else
               do k=1,kk
                  call ccmpi_distribute(var(1:ifull,k),varg(:,k))
               end do
            end if
         else
            if ( kk == kl ) then
               call ccmpi_distribute(var(1:ifull,:))
            else
               do k=1,kk
                  call ccmpi_distribute(var(1:ifull,k))
               end do
            end if
         end if
      end if

   end subroutine readglobvar3

    ! Gather and write a global variable
    ! Optional argument for format
    subroutine writeglobvar2(un,var,fmt)
      include 'newmpar.h'
      integer, intent(in) :: un
      real, dimension(:), intent(in) :: var
      character(len=*), intent(in), optional :: fmt
      real, dimension(ifull_g) :: varg

      if ( myid == 0 ) then
         ! Use explicit ranges here because some arguments might be extended.
         call ccmpi_gather(var(1:ifull),varg)
         if ( present(fmt) ) then
            if ( fmt == "*" ) then
               write(un,*) varg
            else
               write(un,fmt) varg
            end if
         else
            write(un) varg
         end if
      else
         call ccmpi_gather(var(1:ifull))
      end if

   end subroutine writeglobvar2

   subroutine writeglobvar3(un,var,fmt)
      include 'newmpar.h'
      integer, intent(in) :: un
      real, dimension(:,:), intent(in) :: var
      real, dimension(ifull_g,size(var,2)) :: varg
      character(len=*), intent(in), optional :: fmt
      integer :: k, kk

      kk = size(var,2)

      if ( myid == 0 ) then
         ! Use explicit ranges here because some arguments might be extended.
         ! ccmpi_gather3 expects kl, it's not general
         if ( kk == kl ) then
            call ccmpi_gather(var(1:ifull,:),varg)
         else
            do k=1,kk
               call ccmpi_gather(var(1:ifull,k),varg(:,k))
            end do
         end if
         if ( present(fmt) ) then
            if ( fmt == "*" ) then
               write(un,*) varg
            else
               write(un,fmt) varg
            end if
         else
            write(un) varg
         end if
      else
         if ( kk == kl ) then
            call ccmpi_gather(var(1:ifull,:))
         else
            do k=1,kk
               call ccmpi_gather(var(1:ifull,k))
            end do
         end if
      end if

   end subroutine writeglobvar3


end module cc_mpi

