!> This module contains tools to calculate evidence estimators
module evidence_module
    implicit none

    contains


    !> Evidence calculator based on Keeton's paper ([arXiv:1102.0996](http://arxiv.org/abs/1102.0996))
    !!
    !! The evidence calculator recieves the relevent information, namely 
    !! * the loglikelihood of the newly created point ( new_loglikelihood )
    !! * the loglikelihood of the dying point  ( old_loglikelihood )
    !! * number of iterations/dead points ( ndead )
    !!
    !! It ouputs 
    !! * a length 2 vector ( evidence_vec ) with the [evidence, evidence error] in the value of the function
    !! * whether more samples are needed in the logical variable more_samples_needed
    !!
    !! The Keeton evidence calculates using the algorithm outlined in ([arXiv:1102.0996](http://arxiv.org/abs/1102.0996)),
    !! using a moment-based error analysis.
    !!
    !! The algorithm terminates when the contribution from the live evidence is
    !! less than a fraction of the contribution from the dead evidence
    function KeetonEvidence(settings,new_loglikelihood,old_loglikelihood,ndead,more_samples_needed) result (evidence_vec)
        use settings_module
        use utils_module, only: logzero

        implicit none

        ! ------- Inputs ------- 
        !> program settings (mostly useful to pass on the number of live points)
        class(program_settings), intent(in) :: settings

        !> loglikelihood of the newest created point
        double precision,       intent(in) :: new_loglikelihood

        !> loglikelihood of the most recently dead point
        double precision,       intent(in) :: old_loglikelihood

        !> number of dead points/ number of iterations
        integer,                intent(in) :: ndead

        ! ------- Outputs ------- 
        !> Whether we have obtained enough samples for an accurate evidence
        logical,intent(out) :: more_samples_needed

        ! vector containing [logevidence, logevidence error]
        double precision, dimension(2) :: evidence_vec


        ! ------- Local Variables -------

        ! The accumulated evidence associated with the dead points
        ! Z_dead = 1/nlive  sum_k L_k  (nlive/(nlive+1))^k
        double precision, save :: logZ_dead = logzero

        ! The accumulated evidence squared Z^2
        ! Z2_dead = 1/nlive  sum_k L_k  (nlive/(nlive+1))^k * Z2_deadp_k
        double precision, save :: logZ2_dead = logzero

        ! part of the accumulated evidence squared
        ! Z2_deadp = 1/(nlive+1)  sum_k L_k  ((nlive+1)/(nlive+2))^k
        double precision, save :: logZ2_deadp = logzero

        ! the mean log likelihood of the live points
        ! mean_log_like_live = 1/nlive * sum(L_live)
        double precision, save :: logmean_loglike_live=0

        ! Two measures of volume at the kth iteration 
        ! logX_k = (  nlive  /(nlive+1))^k
        ! logY_k = ((nlive+1)/(nlive+2))^k
        double precision :: logX_k,logY_k

        ! The temporary mean and variance to eventually be output in evidence_vec 
        double precision :: logmean, logvariance

        ! number of live points in double precision (taken from settings%nlive)
        double precision :: lognlive 
        double precision :: lognlivep1 
        double precision :: lognlivep2 

        double precision,parameter :: log2 = log(2d0)


        ! Throughout the calculation, we measure all likelihoods relative to


        ! If the function is called with a non-positive ndead, then simply store
        ! the mean_log_likelihood that has been calculated and passed via
        ! new_loglikelihood
        if (ndead <= 0) then
            ! save the average value
            logmean_loglike_live = old_loglikelihood
            more_samples_needed = .true.
            return
        end if


        ! Get the number of live points (and convert to double precision implicitly)
        lognlive = log(settings%nlive+0d0)
        lognlivep1 = log(settings%nlive+1d0)
        lognlivep2 = log(settings%nlive+2d0)


        ! Calculate the volumes
        logX_k = ndead * (lognlive  -lognlivep1)
        logY_k = ndead * (lognlivep1-lognlivep2) 


        ! Add the evidence contribution of the kth dead point to the accumulated dead evidence
        logZ_dead = logaddexp(logZ_dead , old_loglikelihood+ logX_k -lognlive )

        ! Accumulate part of the dead evidence^2
        logZ2_deadp = logaddexp(logZ2_deadp, old_loglikelihood + logY_k -lognlivep1  )

        ! Accumulate the rest of the dead evidence^2
        logZ2_dead = logaddexp(logZ2_dead, old_loglikelihood + logX_k + logZ2_deadp- lognlive )


        ! Add the contribution of the new_loglikelihood from the mean ...
        logmean_loglike_live = logaddexp(logmean_loglike_live, new_loglikelihood -lognlive )

        ! ... and take away the contribution of the 0d0 from the mean
        logmean_loglike_live = logsubexp(logmean_loglike_live, old_loglikelihood -lognlive )



        ! Calculate the mean evidence as a sum of contributions from the dead
        ! and live evidence
        logmean = logaddexp(logZ_dead, logmean_loglike_live + logX_k) 

        ! Calculate the variance in the evidence
        logvariance = logsubexp(log(2d0) +logZ2_dead,2*logZ_dead)                                         ! dead contribution

        logvariance = logaddexp(logvariance,2*logmean_loglike_live + logX_k+logY_k)                       ! live contribution
        logvariance = logsubexp(logvariance,2*logmean_loglike_live + 2*logX_k)                         

        logvariance = logaddexp(logvariance, log(2d0) + logmean_loglike_live + logX_k + logZ2_deadp ) ! cross correlation
        logvariance = logsubexp(logvariance, log(2d0) + logmean_loglike_live + logX_k + logZ_dead       )

        ! Pass the mean and variance to evidence_vec in order to be outputted
        evidence_vec(1) = logmean 
        evidence_vec(2) = logvariance 



        ! Test to see whether we have enough samples. If the contribution from
        ! the live evidence is less than a fraction of the dead evidence, then
        ! we have reached convergence of the algorithm
        if (logmean_loglike_live  + logX_k < log(settings%precision_criterion) + logZ_dead) then
            more_samples_needed = .false.
        else
            more_samples_needed = .true.
        end if



    end function KeetonEvidence


    function logaddexp(a,b)
        implicit none
        double precision :: a
        double precision :: b
        double precision :: logaddexp

        if (a>b) then
            logaddexp = a + log(exp(b-a) + 1)
        else
            logaddexp = b + log(exp(a-b) + 1)
        end if

    end function logaddexp

    function logsubexp(a,b)
        implicit none
        double precision :: a
        double precision :: b
        double precision :: logsubexp

        if(a<b) write(*,*) 'Warning: logsubexp being called incorrectly'
        logsubexp = a + log(1-exp(b-a))

    end function logsubexp


end module evidence_module
