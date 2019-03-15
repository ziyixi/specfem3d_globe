!=====================================================================
!
!          S p e c f e m 3 D  G l o b e  V e r s i o n  7 . 0
!          --------------------------------------------------
!
!     Main historical authors: Dimitri Komatitsch and Jeroen Tromp
!                        Princeton University, USA
!                and CNRS / University of Marseille, France
!                 (there are currently many more authors!)
! (c) Princeton University and CNRS / University of Marseille, April 2014
!
! This program is free software; you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation; either version 3 of the License, or
! (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License along
! with this program; if not, write to the Free Software Foundation, Inc.,
! 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
!
!=====================================================================


  subroutine locate_point(x_target,y_target,z_target,lat_target,lon_target,ispec_selected,xi,eta,gamma, &
                          x,y,z,distmin_not_squared,CAN_BE_BURIED)

! locates target point inside best mesh element

  use constants_solver, only: &
    NGLLX,NGLLY,NGLLZ,MIDX,MIDY,MIDZ,NGNOD,R_EARTH_KM,HUGEVAL, &
    NUM_ITER,USE_DISTANCE_CRITERION

  use specfem_par, only: &
    nspec => NSPEC_CRUST_MANTLE

  use specfem_par_crustmantle, only: &
    ibool => ibool_crust_mantle, &
    xstore => xstore_crust_mantle,ystore => ystore_crust_mantle,zstore => zstore_crust_mantle

  ! for point search
  use specfem_par, only: &
    typical_size_squared, &
    lat_min,lat_max,lon_min,lon_max,xyz_midpoints, &
    xadj,adjncy

  use kdtree_search, only: kdtree_find_nearest_neighbor

  implicit none

  double precision,intent(in) :: x_target,y_target,z_target
  double precision,intent(in) :: lat_target,lon_target

  integer,intent(out) :: ispec_selected
  double precision,intent(out) :: xi,eta,gamma
  double precision,intent(out) :: x,y,z
  double precision,intent(out) :: distmin_not_squared

  logical,intent(in) :: CAN_BE_BURIED

  ! local parameters
  integer :: ix_initial_guess,iy_initial_guess,iz_initial_guess
  integer :: ispec,i,j,k,iglob

  double precision :: lat,lon
  double precision :: distmin_squared,dist_squared

  logical :: target_located
  logical :: use_adjacent_elements_search

  ! nodes search
  double precision,dimension(3) :: xyz_target
  double precision :: dist_min
  integer :: inode_min
  double precision :: xi_n,eta_n,gamma_n,x_n,y_n,z_n ! neighbor position result

  ! neighbors
  integer :: num_neighbors
  integer :: i_n,ientry

  ! brute-force search for closest element
  ! if set to .false., a kd-tree search for initial guess element is used
  logical,parameter :: DO_BRUTE_FORCE_SEARCH = .false.


  ! set distance to huge initial value
  distmin_squared = HUGEVAL

  ! initializes located target
  ! if we have not located a target element, the receiver is not in this slice
  ! therefore use first element only for fictitious iterative search
  ispec_selected = 1
  ix_initial_guess = MIDX
  iy_initial_guess = MIDY
  iz_initial_guess = MIDZ
  use_adjacent_elements_search = .false.

  ! limits latitude to [-90.0,90.0]
  lat = lat_target
  if (lat < -90.d0) lat = -90.d0
  if (lat > 90.d0) lat = 90.d0

  ! limits longitude to [0.0,360.0]
  lon = lon_target
  if (lon < 0.d0) lon = lon + 360.d0
  if (lon > 360.d0) lon = lon - 360.d0

  ! checks if receiver in this slice
  if (lat >= lat_min .and. lat <= lat_max .and. &
      lon >= lon_min .and. lon <= lon_max) then
    target_located = .true.
  else
    target_located = .false.
  endif

  ! debug
  !print *,'target located:',target_located,'lat',sngl(lat),sngl(lat_min),sngl(lat_max),'lon',sngl(lon),sngl(lon_min),sngl(lon_max)

  if (target_located) then
    ! point in this slice
    if (DO_BRUTE_FORCE_SEARCH) then
      ! loops over elements to find nearest location
      ! searches closest GLL point
      if (USE_DISTANCE_CRITERION) then
        ! loops over all elements
        do ispec = 1,nspec
          ! exclude elements that are too far from target
          dist_squared = (x_target - xyz_midpoints(1,ispec))*(x_target - xyz_midpoints(1,ispec)) &
                       + (y_target - xyz_midpoints(2,ispec))*(y_target - xyz_midpoints(2,ispec)) &
                       + (z_target - xyz_midpoints(3,ispec))*(z_target - xyz_midpoints(3,ispec))
          !  we compare squared distances instead of distances themselves to significantly speed up calculations
          if (dist_squared > typical_size_squared) cycle

          ! loop only on points inside the element
          ! exclude edges to ensure this point is not shared with other elements
          do k = 2,NGLLZ-1
            do j = 2,NGLLY-1
              do i = 2,NGLLX-1
                iglob = ibool(i,j,k,ispec)
                dist_squared = (x_target - dble(xstore(iglob)))*(x_target - dble(xstore(iglob))) &
                             + (y_target - dble(ystore(iglob)))*(y_target - dble(ystore(iglob))) &
                             + (z_target - dble(zstore(iglob)))*(z_target - dble(zstore(iglob)))

                !  keep this point if it is closer to the receiver
                !  we compare squared distances instead of distances themselves to significantly speed up calculations
                if (dist_squared < distmin_squared) then
                  distmin_squared = dist_squared
                  ispec_selected = ispec
                  ix_initial_guess = i
                  iy_initial_guess = j
                  iz_initial_guess = k
                endif

              enddo
            enddo
          enddo

        ! end of loop on all the spectral elements in current slice
        enddo
      else
        ! searches through all elements
        do ispec = 1,nspec
          ! loop only on points inside the element
          ! exclude edges to ensure this point is not shared with other elements
          do k = 2,NGLLZ-1
            do j = 2,NGLLY-1
              do i = 2,NGLLX-1
                iglob = ibool(i,j,k,ispec)
                dist_squared = (x_target - dble(xstore(iglob)))*(x_target - dble(xstore(iglob))) &
                             + (y_target - dble(ystore(iglob)))*(y_target - dble(ystore(iglob))) &
                             + (z_target - dble(zstore(iglob)))*(z_target - dble(zstore(iglob)))

                !  keep this point if it is closer to the receiver
                !  we compare squared distances instead of distances themselves to significantly speed up calculations
                if (dist_squared < distmin_squared) then
                  distmin_squared = dist_squared
                  ispec_selected = ispec
                  ix_initial_guess = i
                  iy_initial_guess = j
                  iz_initial_guess = k
                  target_located = .true.
                endif
              enddo
            enddo
          enddo
        ! end of loop on all the spectral elements in current slice
        enddo
      endif ! USE_DISTANCE_CRITERION


      ! to get a good starting point for the iterative refinement,
      ! updates final guess for closest GLL point in the best selected element

      ! note: assumes that before we used looping range from [2, NGLL - 1]
      ! top/bottom surfaces
      do k = 1,NGLLZ,NGLLZ-1
        do j = 1,NGLLY
          do i = 1,NGLLX
            iglob = ibool(i,j,k,ispec_selected)
            dist_squared = (x_target - dble(xstore(iglob)))*(x_target - dble(xstore(iglob))) &
                         + (y_target - dble(ystore(iglob)))*(y_target - dble(ystore(iglob))) &
                         + (z_target - dble(zstore(iglob)))*(z_target - dble(zstore(iglob)))
            ! take this point if it is closer to the receiver
            !  we compare squared distances instead of distances themselves to significantly speed up calculations
            if (dist_squared < distmin_squared) then
              distmin_squared = dist_squared
              ix_initial_guess = i
              iy_initial_guess = j
              iz_initial_guess = k
            endif
          enddo
        enddo
      enddo
      ! front/back surfaces
      do k = 1,NGLLZ
        do j = 1,NGLLY,NGLLY-1
          do i = 1,NGLLX
            iglob = ibool(i,j,k,ispec_selected)
            dist_squared = (x_target - dble(xstore(iglob)))*(x_target - dble(xstore(iglob))) &
                         + (y_target - dble(ystore(iglob)))*(y_target - dble(ystore(iglob))) &
                         + (z_target - dble(zstore(iglob)))*(z_target - dble(zstore(iglob)))
            ! take this point if it is closer to the receiver
            !  we compare squared distances instead of distances themselves to significantly speed up calculations
            if (dist_squared < distmin_squared) then
              distmin_squared = dist_squared
              ix_initial_guess = i
              iy_initial_guess = j
              iz_initial_guess = k
            endif
          enddo
        enddo
      enddo
      ! left/right surfaces
      do k = 1,NGLLZ
        do j = 1,NGLLY
          do i = 1,NGLLX,NGLLX-1
            iglob = ibool(i,j,k,ispec_selected)
            dist_squared = (x_target - dble(xstore(iglob)))*(x_target - dble(xstore(iglob))) &
                         + (y_target - dble(ystore(iglob)))*(y_target - dble(ystore(iglob))) &
                         + (z_target - dble(zstore(iglob)))*(z_target - dble(zstore(iglob)))
            ! take this point if it is closer to the receiver
            !  we compare squared distances instead of distances themselves to significantly speed up calculations
            if (dist_squared < distmin_squared) then
              distmin_squared = dist_squared
              ix_initial_guess = i
              iy_initial_guess = j
              iz_initial_guess = k
            endif
          enddo
        enddo
      enddo

    else
      ! kdtree search
      xyz_target(1) = x_target
      xyz_target(2) = y_target
      xyz_target(3) = z_target

      ! finds closest point (inside GLL points) in this chunk
      call kdtree_find_nearest_neighbor(xyz_target,inode_min,dist_min)

      ! debug
      !print *,'kd-tree found location :',inode_min

      ! sets element
      ispec_selected = inode_min

      ! loops over GLL points in this element to get (i,j,k) for initial guess
      do k = 1,NGLLZ
        do j = 1,NGLLY
          do i = 1,NGLLX
            iglob = ibool(i,j,k,ispec_selected)
            dist_squared = (x_target - dble(xstore(iglob)))*(x_target - dble(xstore(iglob))) &
                         + (y_target - dble(ystore(iglob)))*(y_target - dble(ystore(iglob))) &
                         + (z_target - dble(zstore(iglob)))*(z_target - dble(zstore(iglob)))
            ! take this point if it is closer to the receiver
            !  we compare squared distances instead of distances themselves to significantly speed up calculations
            if (dist_squared < distmin_squared) then
              distmin_squared = dist_squared
              ix_initial_guess = i
              iy_initial_guess = j
              iz_initial_guess = k
            endif
          enddo
        enddo
      enddo
    endif ! DO_BRUTE_FORCE_SEARCH

    ! checks if initial guess lies on an element boundary
    if ((ix_initial_guess == 1 .or. ix_initial_guess == NGLLX) .or. &
        (iy_initial_guess == 1 .or. iy_initial_guess == NGLLY) .or. &
        (iz_initial_guess == 1 .or. iz_initial_guess == NGLLZ)) then
      ! best guess close to a GLL point on an element boundary
      use_adjacent_elements_search = .true.
    else
      use_adjacent_elements_search = .false.
    endif

    !debug
    !print *,'initial guess ',ix_initial_guess,iy_initial_guess,iz_initial_guess,ispec_selected,use_adjacent_elements_search

  endif ! target_located


  ! ****************************************
  ! find the best (xi,eta,gamma)
  ! ****************************************
  if (target_located) then

!      ! for point sources, the location will be exactly at a GLL point
!      ! otherwise this tries to find best location
!
!      if (USE_FORCE_POINT_SOURCE) then
!        ! store xi,eta,gamma and x,y,z of point found
!        ! note: they have range [1.0d0,NGLLX/Y/Z], used for point sources
!        !          see e.g. in compute_add_sources.f90
!        xi_subset(isource_in_this_subset) = dble(ix_initial_guess)
!        eta_subset(isource_in_this_subset) = dble(iy_initial_guess)
!        gamma_subset(isource_in_this_subset) = dble(iz_initial_guess)
!
!        iglob = ibool(ix_initial_guess,iy_initial_guess, &
!            iz_initial_guess,ispec_selected)
!        xyz_found_subset(1,isource_in_this_subset) = xstore(iglob)
!        xyz_found_subset(2,isource_in_this_subset) = ystore(iglob)
!        xyz_found_subset(3,isource_in_this_subset) = zstore(iglob)
!
!        ! compute final distance between asked and found (converted to km)
!        final_distance_subset(isource_in_this_subset) = &
!          dsqrt((x_target-xyz_found_subset(1,isource_in_this_subset))**2 + &
!                (y_target-xyz_found_subset(2,isource_in_this_subset))**2 + &
!                (z_target-xyz_found_subset(3,isource_in_this_subset))**2)*R_EARTH/1000.d0
!
!      else

    ! gets xi/eta/gamma and corresponding x/y/z coordinates
    call find_local_coordinates(x_target,y_target,z_target,xi,eta,gamma,x,y,z, &
                                ispec_selected,ix_initial_guess,iy_initial_guess,iz_initial_guess, &
                                CAN_BE_BURIED)
    ! best distance to target .. so far
    distmin_squared = (x_target - x)*(x_target - x) &
                    + (y_target - y)*(y_target - y) &
                    + (z_target - z)*(z_target - z)

    ! checks if position lies on an element boundary
    if (abs(xi) > 1.099d0 .or. abs(eta) > 1.099d0 .or. abs(gamma) > 1.099d0) then
      ! best guess close to an element boundary
      use_adjacent_elements_search = .true.
    else
      use_adjacent_elements_search = .false.
    endif

    !debug
    !print *,'best guess ',xi,eta,gamma,use_adjacent_elements_search,'distance',sqrt(distmin_squared)*R_EARTH_KM

    ! loops over neighbors and try to find better location
    if (use_adjacent_elements_search) then

      ! adjacency arrays
      num_neighbors = xadj(ispec_selected+1)-xadj(ispec_selected)

      ! debug
      !print *,'neighbors',num_neighbors,ispec_selected,xadj(ispec_selected+1),xadj(ispec_selected)

      ! loops over neighbors
      do i_n = 1,num_neighbors
        ! get neighbor
        ientry = xadj(ispec_selected) + i_n
        ispec = adjncy(ientry)

        ! debug
        !print *,'neighbor ',ispec,i_n,ientry,ispec_selected

        ! checks
        if (ispec < 1 .or. ispec > nspec) stop 'Invalid ispec index in locate point search'

        ! gets xi/eta/gamma and corresponding x/y/z coordinates
        call find_local_coordinates(x_target,y_target,z_target,xi_n,eta_n,gamma_n,x_n,y_n,z_n, &
                                    ispec,MIDX,MIDY,MIDZ,CAN_BE_BURIED)

        ! distance to target
        dist_squared = (x_target - x_n)*(x_target - x_n) &
                     + (y_target - y_n)*(y_target - y_n) &
                     + (z_target - z_n)*(z_target - z_n)

        ! take this point if it is closer to the receiver
        !  we compare squared distances instead of distances themselves to significantly speed up calculations
        if (dist_squared < distmin_squared) then
          distmin_squared = dist_squared
          ! uses this as new location
          ispec_selected = ispec
          xi = xi_n
          eta = eta_n
          gamma = gamma_n
          x = x_n
          y = y_n
          z = z_n
        endif

      enddo ! num_neighbors

      !debug
      !print *,'best neighbor ',xi,eta,gamma,ispec_selected,'distance',sqrt(distmin_squared)*R_EARTH_KM

    endif ! use_adjacent_element_search

  else
    ! point not found in this slice
    iglob = ibool(ix_initial_guess,iy_initial_guess,iz_initial_guess,ispec_selected)
    x = dble(xstore(iglob))
    y = dble(xstore(iglob))
    z = dble(xstore(iglob))
    xi = 0.d0
    eta = 0.d0
    gamma = 0.d0
  endif

  ! compute final distance between asked and found (converted to km)
  distmin_not_squared = dsqrt((x_target-x)**2 + &
                              (y_target-y)**2 + &
                              (z_target-z)**2)*R_EARTH_KM

  end subroutine locate_point

!
!-------------------------------------------------------------------------------------------------
!

  subroutine find_local_coordinates(x_target,y_target,z_target,xi,eta,gamma,x,y,z, &
                                   ispec_selected,ix_initial_guess,iy_initial_guess,iz_initial_guess, &
                                   CAN_BE_BURIED)

  use constants_solver, only: &
    NGNOD,HUGEVAL,NUM_ITER

  use specfem_par_crustmantle, only: &
    ibool => ibool_crust_mantle, &
    xstore => xstore_crust_mantle,ystore => ystore_crust_mantle,zstore => zstore_crust_mantle

  ! for point search
  use specfem_par, only: &
    anchor_iax,anchor_iay,anchor_iaz, &
    xigll,yigll,zigll

  implicit none

  double precision,intent(in) :: x_target,y_target,z_target
  double precision,intent(out) :: xi,eta,gamma
  double precision,intent(out) :: x,y,z

  integer,intent(in) :: ispec_selected,ix_initial_guess,iy_initial_guess,iz_initial_guess

  logical,intent(in) :: CAN_BE_BURIED

  ! local parameters
  integer :: ia,iter_loop
  integer :: iglob

  ! coordinates of the control points of the surface element
  double precision :: xelm(NGNOD),yelm(NGNOD),zelm(NGNOD)

  double precision :: dx,dy,dz,dx_min,dy_min,dz_min,d_min_sq
  double precision :: dxi,deta,dgamma
  double precision :: xix,xiy,xiz
  double precision :: etax,etay,etaz
  double precision :: gammax,gammay,gammaz

  ! define coordinates of the control points of the element
  do ia = 1,NGNOD
    iglob = ibool(anchor_iax(ia),anchor_iay(ia),anchor_iaz(ia),ispec_selected)
    xelm(ia) = dble(xstore(iglob))
    yelm(ia) = dble(ystore(iglob))
    zelm(ia) = dble(zstore(iglob))
  enddo

  ! use initial guess in xi and eta
  xi = xigll(ix_initial_guess)
  eta = yigll(iy_initial_guess)
  gamma = zigll(iz_initial_guess)

  ! impose receiver exactly at the surface
  if (.not. CAN_BE_BURIED) gamma = 1.d0

  d_min_sq = HUGEVAL
  dx_min = HUGEVAL
  dy_min = HUGEVAL
  dz_min = HUGEVAL

  ! iterate to solve the non linear system
  do iter_loop = 1,NUM_ITER

    ! recompute Jacobian for the new point
    call recompute_jacobian(xelm,yelm,zelm,xi,eta,gamma,x,y,z, &
                            xix,xiy,xiz,etax,etay,etaz,gammax,gammay,gammaz)

    ! compute distance to target location
    dx = - (x - x_target)
    dy = - (y - y_target)
    dz = - (z - z_target)

    !debug
    !print *,'  iter ',iter_loop,'dx',sngl(dx),sngl(dx_min),'dy',sngl(dy),sngl(dy_min),'dz',sngl(dz),sngl(dz_min),d_min_sq

    ! compute increments
    if ((dx**2 + dy**2 + dz**2) < d_min_sq) then
      d_min_sq = dx**2 + dy**2 + dz**2
      dx_min = dx
      dy_min = dy
      dz_min = dz

      dxi = xix*dx + xiy*dy + xiz*dz
      deta = etax*dx + etay*dy + etaz*dz
      dgamma = gammax*dx + gammay*dy + gammaz*dz
    else
      ! new position is worse than old one, no change necessary
      dxi = 0.d0
      deta = 0.d0
      dgamma = 0.d0
    endif

    ! decreases step length if step is large
    if ((dxi**2 + deta**2 + dgamma**2) > 1.0d0) then
      dxi = dxi * 0.33333333333d0
      deta = deta * 0.33333333333d0
      dgamma = dgamma * 0.33333333333d0
    endif
    ! alternative: impose limit on increments (seems to result in slightly less accurate locations)
    !if (abs(dxi) > 0.3d0 ) dxi = sign(1.0d0,dxi)*0.3d0
    !if (abs(deta) > 0.3d0 ) deta = sign(1.0d0,deta)*0.3d0
    !if (abs(dgamma) > 0.3d0 ) dgamma = sign(1.0d0,dgamma)*0.3d0

    !debug
    !print *,'  dxi/..',(dxi**2 + deta**2 + dgamma**2),dxi,deta,dgamma

    ! update values
    xi = xi + dxi
    eta = eta + deta
    gamma = gamma + dgamma

    ! impose that we stay in that element
    ! (useful if user gives a receiver outside the mesh for instance)
    ! we can go slightly outside the [1,1] segment since with finite elements
    ! the polynomial solution is defined everywhere
    ! can be useful for convergence of iterative scheme with distorted elements
    if (xi > 1.10d0) xi = 1.10d0
    if (xi < -1.10d0) xi = -1.10d0
    if (eta > 1.10d0) eta = 1.10d0
    if (eta < -1.10d0) eta = -1.10d0
    if (gamma > 1.10d0) gamma = 1.10d0
    if (gamma < -1.10d0) gamma = -1.10d0

  ! end of non linear iterations
  enddo

  ! impose receiver exactly at the surface
  if (.not. CAN_BE_BURIED) gamma = 1.d0

  ! compute final coordinates of point found
  call recompute_jacobian(xelm,yelm,zelm,xi,eta,gamma,x,y,z, &
                          xix,xiy,xiz,etax,etay,etaz,gammax,gammay,gammaz)

  end subroutine find_local_coordinates