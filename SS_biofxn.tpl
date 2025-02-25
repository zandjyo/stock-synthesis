//*********************************************************************
 /*  SS_Label_Function_14 #Get_MGsetup:  apply time-varying factors this year to the MG parameters to create mgp_adj vector */
FUNCTION void get_MGsetup(const int yz)
  {
    mgp_adj=MGparm;  //  set all to base parm value
//    int y1;

    for (f=1;f<=N_MGparm;f++)
    {
      if(MGparm_timevary(f)>0)   // timevary
      {
        mgp_adj(f)=parm_timevary(MGparm_timevary(f),yz);
        if(parm_adjust_method==1 && (save_for_report>0 || do_once==1))
        {
          if(mgp_adj(f)<MGparm_1(f,1) || mgp_adj(f)>MGparm_1(f,2))
          {
            N_warn++;
             warning<<N_warn<<" "<<" adjusted MGparm out of bounds (Phase, Iter, parm#, yr, min, max, base, adj_value) "<<current_phase()<<" "<<niter<<f<<" "<<yz<<" "<<
            MGparm_1(f,1)<<" "<<MGparm_1(f,2)<<" "<<MGparm(f)<<" "<<mgp_adj(f)<<" "<<ParmLabel(f)<<endl;
          }
        }
      }
    }  // end parm loop

  //  SS_Label_Info_14.5 #if MGparm method =1 (no offsets), then do direct assignment if parm value is 0.0. (only for natMort and growth parms)
    if(MGparm_def==1)
    {
      for (j=1;j<=N_MGparm;j++)
      {
        if(MGparm_offset(j)>0) mgp_adj(j) = mgp_adj(MGparm_offset(j));
      }
    }
  if(save_for_report>0) mgp_save(yz)=value(mgp_adj);
  }


//********************************************************************
 /*  SS_Label_FUNCTION 15 get_growth1;  calc some seasonal and CV_growth biology factors that cannot be time-varying */
FUNCTION void get_growth1()
  {
  //  SS_Label_Info_15.1  #create seasonal effects for growth K, and for wt_len parameters
    if(MGparm_doseas>0)
    {
      if(MGparm_seas_effects(10)>0)  // for seasonal K
      {
        VBK_seas(0)=0.0;
        for (s=1;s<=nseas;s++)
        {
          VBK_seas(s)=mfexp(MGparm(MGparm_seas_effects(10)+s));
          VBK_seas(0)+=VBK_seas(s)*seasdur(s);
        }
      }
      else
      {
        VBK_seas=sum(seasdur);  // set vector to null effect
      }
      for(gp=1;gp<=N_GP;gp++)
      for (j=1;j<=8;j++)
      {
 #ifdef DO_ONCE
        {if (do_once==1) echoinput<<j<<"  wt_len seas "<<MGparm_seas_effects(j)<<endl;}
 #endif
        if(MGparm_seas_effects(j)>0)
        {
          wtlen_seas(0,gp,j)=0.0;
          for (s=1;s<=nseas;s++)
          {
            wtlen_seas(s,gp,j)=mfexp(MGparm(MGparm_seas_effects(j)+s));
            wtlen_seas(0,gp,j)+=wtlen_seas(s,gp,j)*seasdur(s);  //  this seems not to be used
          }
        }
        else
        {
          for (s=0;s<=nseas;s++) {wtlen_seas(s,gp,j)=1.0;}
        }
      }
    }
    else
    {
      VBK_seas=sum(seasdur);  // set vector to null effect
      for(s=1;s<=nseas;s++) wtlen_seas(s)=1.0;  // set vector to null effect
    }

  //  SS_Label_Info_15.2  #create variability of size-at-age factors using direct assignment or offset approaches
      gp=0;
      for (gg=1;gg<=gender;gg++)
      for (g=1;g<=N_GP;g++)
      {
        gp++;
        Ip=MGparm_point(gg,g);
        j=Ip+N_M_Grow_parms-2;  // index for CVmin
        k=j+1;  // index for CVmax
        switch(MGparm_def)    // for CV of size-at-age
          {
            case 1:  // direct
            {
            if(MGparm(j)>0)
              {CVLmin(gp)=MGparm(j);} else {CVLmin(gp)=MGparm(N_M_Grow_parms-1);}
            if(MGparm(k)>0)
              {CVLmax(gp)=MGparm(k);} else {CVLmax(gp)=MGparm(N_M_Grow_parms);}
            break;
            }
            case 2:  // offset
            {
            if(gp==1)
              {CVLmin(gp)=MGparm(j); CVLmax(gp)=MGparm(k);}
            else
              {CVLmin(gp)=CVLmin(1)*mfexp(MGparm(j)); CVLmax(gp)=CVLmax(1)*mfexp(MGparm(k));}
            break;
            }
            case 3:  // offset like SS2 V1.23
            {
            if(gp==1)
              {CVLmin(gp)=MGparm(j); CVLmax(gp)=CVLmin(1)*mfexp(MGparm(k));}
            else
              {CVLmin(gp)=CVLmin(1)*mfexp(MGparm(j)); CVLmax(gp)=CVLmin(gp)*mfexp(MGparm(k));}
            break;
            }
          }  // end switch
          if((CVLmin(gp)!=CVLmax(gp)) || active(MGparm(N_M_Grow_parms)) || active(MGparm(k)))
          {CV_const(gp)=1;} else {CV_const(gp)=0;}
        }
  }

//********************************************************************
 /*  SS_Label_Function_ 16 #get_growth2; (do seasonal growth calculations for a selected year) */
FUNCTION void get_growth2(const int y)
  {
//  called at beginning of each year, so y is known
//  if y=styr, then does equilibrium size-at-age according to start year growth parameters
//  for any year, calculates for each season the size at the beginning of the next season, with growth increment calculated according to that year's parameters 

//Growth Cessation Model code added by Mark Maunder October 2018
//The growth cessation model is described in 
//Maunder, M.N., Deriso, R.B., Schaefer, K.M., Fuller, D.W., Aires-da-Silva, A.M., Minte‑Vera, C.V., Campana, S.E. 2018. The growth cessation model: a growth model for species showing a near cessation in growth with application to bigeye tuna (Thunnus obesus). Marine Biology (2018) 165:76. 
//Ian Taylor derived the formula for Linf

    int k2;
    int add_age;
    int ALK_idx2;  //  beginning of first subseas of next season
    dvariable plusgroupsize;
    dvariable current_size;
    dvariable VBK_temp;
    dvariable VBK_temp2;  //  with VBKseas(s) multiplied
    dvariable LminR;
    dvariable LmaxR;
    dvariable LinfR;
    dvariable inv_Richards;
    dvariable t50;
  //  SS_Label_Info_16.1 #Create Cohort_Growth offset for the cohort borne (age 0) this year
    if(CGD_onoff>0)   //  cohort specific growth multiplier
    {
      temp=mgp_adj(MGP_CGD);
      k=min(nages,(YrMax-y));
      for (a=0;a<=k;a++) {Cohort_Growth(y+a,a)=temp;}  //  so this multiplier on growth_increment is stored on a diagonal into the future
    }

  //  SS_Label_Info_16.2 #Loop growth patterns (sex*N_GP)
    gp=0;
 #ifdef DO_ONCE
  {if(do_once==1)  echoinput<<"GROWTH,  yr= "<<y<<endl;}
 #endif
    for(gg=1;gg<=gender;gg++)
    for (GPat=1;GPat<=N_GP;GPat++)
    {
      gp++;
      Ip=MGparm_point(gg,GPat)+N_natMparms;
      switch(Grow_type)   //  create specific growth parameters from the mgp_adj list of current MGparms
      {
        case 7:  //  empirical length
        {
          break;
        }

        default:  //  process parameters for all other grow_type
        {
//  SS_Label_Info_16.2.1  #set Lmin, Lmax, VBK, Richards to this year's values for mgp_adj
          if(MGparm_def>1 && gp>1)  // do offset approach
          {
            Lmin(gp)=Lmin(1)*mfexp(mgp_adj(Ip));
            Lmax_temp(gp)=Lmax_temp(1)*mfexp(mgp_adj(Ip+1));
            VBK(gp)=VBK(1)*mfexp(mgp_adj(Ip+2));  //  assigns to all ages for which VBK is defined
          }
          else
          {
            Lmin(gp)=mgp_adj(Ip);
            Lmax_temp(gp)=mgp_adj(Ip+1);  //  size at A2; could be 999 to indicate Linf
            VBK(gp)=-mgp_adj(Ip+2);  // because always used as negative; assigns to all ages for which VBK is defined
          }
          VBK_temp=VBK(gp,0);  //  will be reset to VBK(gp,nages) if using age-specific K

    //  SS_Label_Info_16.2.2  #Set up age specific k
            if(Grow_type==3)  //  age specific k
            {
              j=1;
              for (a=1;a<=nages;a++)
              {
                if(a==Age_K_points(j))
                {
                  VBK(gp,a)=VBK(gp,a-1)*mgp_adj(Ip+2+j);
                  if(j<Age_K_count) j++;
                }
                else
                {
                  VBK(gp,a)=VBK(gp,a-1);
                }
              }
              VBK_temp=VBK(gp,nages);
            }
            else if(Grow_type==4)  //  age specific k  reverse order, so age_k_points need to be descending
            {
              j=1;
              VBK(gp,nages)=VBK_temp;
              for (a=nages-1;a>=0;a--)
              {
                if(a==Age_K_points(j))
                {
                  VBK(gp,a)=VBK(gp,a+1)*mgp_adj(Ip+2+j);
                  if(j<Age_K_count) j++;
                }
                else
                {
                  VBK(gp,a)=VBK(gp,a+1);
                }
              }
            }
            else if(Grow_type==5)  //  age specific k replacement, so age_k_points need to be descending
            {
              j=1;
              for (a=nages;a>=0;a--)
              {
                if(a==Age_K_points(j))
                {
                  VBK(gp,a)=mgp_adj(Ip+2+j)*VBK_temp;
                  if(j<Age_K_count) j++;
                }
                else
                {
                  VBK(gp,a)=VBK_temp;
                }
              }
              VBK_temp=VBK(gp,nages);
            }

//  get Linf from Lmax
//  get Richards or growth cessation parameter if appropriate
          if(Grow_type==2)  //  Richards
          {
            if(MGparm_def>1 && gp>1)
            {
              Richards(gp)=Richards(1)*mfexp(mgp_adj(Ip+3));
            }
            else
            {
              Richards(gp)=mgp_adj(Ip+3);
            }
            LminR=pow(Lmin(gp),Richards(gp));
            inv_Richards=1.0/Richards(gp);
            if(AFIX2==999)
            {
              L_inf(gp)=Lmax_temp(gp);
              LinfR=pow(L_inf(gp),Richards(gp));
            }
            else
            {
              LmaxR=pow(Lmax_temp(gp), Richards(gp));
              LinfR=LminR+(LmaxR-LminR)/(1.-mfexp(VBK_temp*VBK_seas(0)*(AFIX_delta)));
              L_inf(gp)=pow(LinfR,inv_Richards);
            }
 #ifdef DO_ONCE
            if (do_once==1) echoinput<<" linf  "<<L_inf(gp)<<"   VBK: "<<VBK_temp<<endl;
 #endif
          }
          else if(Grow_type==8)
          {
            if(MGparm_def>1 && gp>1)
            {Richards(gp)=Richards(1)*mfexp(mgp_adj(Ip+3));}
            else
            {Richards(gp)=mgp_adj(Ip+3);}
            L_inf(gp)=Lmax_temp(gp);
            VBK_temp=-VBK(gp,0)*VBK_seas(0);
            // t50 is the calculated inflection age for the decline in K
            t50=log(exp((L_inf(gp)-Lmin(gp))*Richards(gp)/VBK_temp)-1.0)/Richards(gp);
          }
          else
          {
            if(AFIX2==999)
            {L_inf(gp)=Lmax_temp(gp);}
            else
            {L_inf(gp)=Lmin(gp)+(Lmax_temp(gp)-Lmin(gp))/(1.-mfexp(VBK_temp*VBK_seas(0)*(AFIX_delta)));
 #ifdef DO_ONCE
            if(do_once==1) echoinput<<VBK_temp<<" "<<VBK_seas(0)<<" "<<VBK_temp*VBK_seas(0)<<" "<<Lmax_temp(gp)<<" "<<L_inf(gp)<<endl;
 #endif
              }

          }

    //  SS_Label_Info_16.2.3  #Set up Lmin and Lmax in Start Year
          if(y==styr)
          {
            Cohort_Lmin(gp)=Lmin(gp);   //  sets for all years and ages
          }
          else if(timevary_MG(y,2)>0)  //  using time-vary growth
          {
            k=min(nages,(YrMax-y));
            for (a=0;a<=k;a++) {Cohort_Lmin(gp,y+a,a)=Lmin(gp);}  //  sets for future years so cohort remembers its size at birth; with Lmin(gp) being size at birth this year
          }
        }  //  end setup of parametric growth parameters
      }  //  end switch between parametric and non-parametric growth
 #ifdef DO_ONCE
      if(do_once==1) {
        echoinput<<"sex: "<<gg<<" GP: "<<gp<<" Lmin: "<<Lmin(gp)<<" Linf: "<<L_inf(gp)<<" VBK_temp: "<<VBK_temp<<" VBK@age: "<<-VBK(gp)<<endl;
        if(Grow_type==2)  echoinput<<"  Richards: "<<Richards(gp)<<endl;
        if(Grow_type==8)  echoinput<<"  Cessation_decay: "<<Richards(gp)<<endl;
        }
 #endif
//  SS_Label_Info_16.2.4  #Loop settlement events because growth starts at time of settlement
      g=g_Start(gp);  //  base platoon
      for (settle=1;settle<=N_settle_timings;settle++)
      {
        g+=N_platoon;  //  increment by N_platoon because only middle platoon has growth modeled
        if(use_morph(g)>0)
        {
          if(y==styr)
          {
            switch(Grow_type)
            {
              case 7:  //  non-parametric
              {
                break;
              }
              default:
              {
//  SS_Label_Info_16.2.4.1  #set up the delta in growth variability across ages if needed
                if(CV_const(gp)>0)
                {
                  if(CV_depvar_a==0)
                    {CV_delta(gp)=(CVLmax(gp)-CVLmin(gp))/(Lmax_temp(gp)-Lmin(gp));}
                  else
                    {CV_delta(gp)=(CVLmax(gp)-CVLmin(gp))/(AFIX2_forCV-AFIX);}
                }
                else
                {
                  CV_delta(gp)=0.0;
                  CV_G(gp)=CVLmin(gp);  // sets all seasons and whole age range
                }
              }
            }

//  SS_Label_Info_16.2.4.1.1  #if y=styr, get size-at-age in first subseason of first season of this first year
            switch (Grow_type)
            {
              case 1:
              {
                VBK_temp2=VBK_temp*VBK_seas(0);
                for (a=0;a<=nages;a++)
                {
//                    Ave_Size(styr,1,g,a) = Lmin(gp) + (Lmin(gp)-L_inf(gp))* (mfexp(VBK_temp2*(real_age(g,1,a)-AFIX))-1.0);
                    Ave_Size(styr,1,g,a) = L_inf(gp) + (Lmin(gp)-L_inf(gp))* mfexp(VBK_temp2*(real_age(g,1,a)-AFIX));
                }  // done ageloop
                break;
              }
              case 2:  // Richards
              {
                Ave_Size(styr,1,g)(0,first_grow_age(g)) = Lmin(gp);
                VBK_temp2=VBK_temp*VBK_seas(0);
                for (a=first_grow_age(g);a<=nages;a++)
                {
                  temp=LinfR + (LminR-LinfR)*mfexp(VBK_temp2*(real_age(g,1,a)-AFIX));
                  Ave_Size(styr,1,g,a) = pow(temp,inv_Richards);
                }  // done ageloop
                break;
              }
              case 5:
              {}
              case 4:
              {}
              case 3:  //  age-specific K, so need age-by-age calculations
              {
                ALK_idx=1;
                //VBK_seas(0) accounts for season duration
                for (a=0;a<=nages;a++)
                {
                  k2=a-1;
                  if(lin_grow(g,ALK_idx,a)>=-1.0)  // linear segment, or first time point beyond AFIX;
                  {Ave_Size(styr,1,g,a) = Lmin(gp) + (Lmin(gp)-L_inf(gp))* (mfexp(VBK(gp,0)*VBK_seas(0)*(real_age(g,1,a)-AFIX))-1.0);}
                  else
                  {
                    Ave_Size(styr,1,g,a) = Ave_Size(styr,1,g,k2) + (mfexp(VBK(gp,k2)*VBK_seas(0))-1.0)*(Ave_Size(styr,1,g,k2)-L_inf(gp));
                  }
//                  echoinput<<a<<" "<<lin_grow(g,ALK_idx,a)<<" "<<real_age(g,1,a)-AFIX<<" "<<Ave_Size(styr,1,g,a) <<endl;
                }  // done ageloop
                break;
              }
			        case 8:  // Growth Cessation Model
              {
          //  r_max (parameter related to maximum growth rate) = vbktemp
          //  L0 (mean length at age 0)
          //  Linf (asymptotic mean length)
          //  k (steepness of the logistic function that models the reduction in the growth increment) = Richards
                VBK_temp2=VBK_temp*VBK_seas(0);
                Ave_Size(styr,1,g)(0,first_grow_age(g)) = Lmin(gp); //assume first_grow_age(g) = 0 
                for (a=first_grow_age(g);a<=nages;a++)
                {
				          Ave_Size(styr,1,g,a) = Lmin(gp)+VBK_temp2*((log(exp(-Richards(gp)*t50)+1)-log(exp(Richards(gp)*(real_age(g,1,a)-AFIX-t50))+1))/Richards(gp)+real_age(g,1,a)-AFIX);  
                }  // done ageloop
                break;
              }
            }
 #ifdef DO_ONCE
            if(do_once==1) echoinput<<"  settlement: "<<settle<<" g: "<<g<<endl<<"  L@A initial_year (w/o lin): "<<Ave_Size(styr,1,g)(0,min(6,nages))<<" plusgroup: "<<Ave_Size(styr,1,g,nages)<<endl;
 #endif

//  SS_Label_Info_16.2.4.1.4  #calc approximation to mean size at maxage to account for growth after reaching the maxage (accumulator age)
            current_size=Ave_Size(styr,1,g,nages);
            if(Linf_decay>-997.)  //  decay rate has been read;  uses same code for Richards and standard
            {
              temp1=1.0;
              temp4=1.0;
              temp=current_size;
              temp2=mfexp(-Linf_decay);  //  cannot use natM or Z because growth is calculated first
 #ifdef DO_ONCE
              if(do_once==1) echoinput<<" L_inf "<<L_inf(gp)<<" size@exactly maxage "<<current_size<<endl;
 #endif
              if(Grow_type<3)
                {VBK_temp2=VBK(gp,0);}
                else
                {VBK_temp2=VBK(gp,nages);}
              VBK_temp2=(1.0-mfexp(VBK_temp2*VBK_seas(0)));
              for (a=nages+1;a<=3*nages;a++)
              {
                temp4*=temp2;  //  decay numbers at age by exp(-0.xxx)
                current_size+=(L_inf(gp)-current_size)*VBK_temp2;
                temp+=temp4*current_size;
                temp1+=temp4;   //  accumulate numbers to create denominator for mean size calculation
              }
              Ave_Size(styr,1,g,nages)=temp/temp1;  //  this is weighted mean size at nages
            }
            else if (Linf_decay==-999.) //  mimic SS3.24
            {
              temp=0.0;
              temp1=0.0;
              temp2=mfexp(-0.2);  //  cannot use natM or Z because growth is calculated first
              temp3=L_inf(gp)-current_size;  // delta between linf and the size at nages
              //  frac_ages = age/nages, so is fraction of a lifetime
              temp4=1.0;
              for (a=0;a<=nages;a++)
              {
                temp+=temp4*(current_size+frac_ages(a)*temp3);  // so grows linearly from size at nages to size at nages+nages
                temp1+=temp4;   //  accumulate numbers to create denominator for mean size calculation
                temp4*=temp2;  //  decay numbers at age by exp(-0.2)
              }
              Ave_Size(styr,1,g,nages)=temp/temp1;  //  this is weighted mean size at nages
            }
            else
            {
               //  no adjustment   
            }
 #ifdef DO_ONCE
            if(do_once==1) echoinput<<"  adjusted size at maxage "<<Ave_Size(styr,1,g,nages)<<"  using decay of: "<<Linf_decay<<endl;
 #endif
          }  //  end initial year calcs

//  SS_Label_Info_16.2.4.2  #loop seasons for growth calculation
          for (s=1;s<=nseas;s++)
          {
            t=t_base+s;
            ALK_idx=s*N_subseas;  // last subseas of season; so checks to see if still in linear phase at end of this season
            if(s==nseas)
            {
              ALK_idx2=1;  //  first subseas of next year
            }
            else
            {
              ALK_idx2=s*N_subseas+1;  //  for the beginning of first subseas of next season
            }
            if(s==nseas) add_age=1; else add_age=0;   //      advance age or not
// growth to next season
            VBK_temp2=(mfexp(VBK_temp*seasdur(s)*VBK_seas(s))-1.0);
            switch (Grow_type)
            {
              case 1:
              {
                for (a=0;a<=nages;a++)
                {
                  if(a==nages) {k2=a;} else {k2=a+add_age;}  // where add_age =1 if s=nseas, else 0  (k2 assignment could be in a matrix so not recalculated
    // NOTE:  there is no seasonal interpolation, or real age adjustment for age-specific K.  Maybe someday....
                  if(lin_grow(g,ALK_idx,a)==-2.0)  //  so doing growth curve
                  {
                    t2=Ave_Size(t,1,g,a)-L_inf(gp);  //  remaining growth potential from first subseas
                    if(timevary_MG(y,2)>0 && t2>-1.)
                    {
                      join1=1.0/(1.0+mfexp(-(50.*t2/(1.0+fabs(t2)))));  //  note the logit transform is not perfect, so growth near Linf will not be exactly same as with native growth function
                      t2*=(1.-join1);  // trap to prevent decrease in size-at-age
                    }

    //  SS_Label_info_16.2.4.2.1.1  #calc size at end of the season, which will be size at begin of next season using current seasons growth parms
                      //  with k2 adding an age if at the end of the year
                    if((a<nages || s<nseas)) Ave_Size(t+1,1,g,k2) = Ave_Size(t,1,g,a) + VBK_temp2*t2*Cohort_Growth(y,a);
                    if(a==nages && s==nseas) {plusgroupsize = Ave_Size(t,1,g,nages) + VBK_temp2*t2*Cohort_Growth(y,nages);}
                  }
                  else if(lin_grow(g,ALK_idx,a)==-1.0)  // first time point beyond AFIX;  lin_grow will stay at -1 for all remaining subseas of this season
                  {
                    Ave_Size(t+1,1,g,k2) = Cohort_Lmin(gp,y,a) + (Cohort_Lmin(gp,y,a)-L_inf(gp))*
                    (mfexp(VBK_temp*(real_age(g,ALK_idx2,k2)-AFIX)*VBK_seas(s))-1.0)*Cohort_Growth(y,a);
                  }
                  else  // in linear phase
                  {
                    Ave_Size(t+1,1,g,a) = len_bins(1)+lin_grow(g,ALK_idx,a)*(Cohort_Lmin(gp,y,a)-len_bins(1));
                  }
                }  // done ageloop
                break;
              }
              case 2: // Richards
              {
                for (a=0;a<=nages;a++)
                {
                  if(a==nages) {k2=a;} else {k2=a+add_age;}  // where add_age =1 if s=nseas, else 0  (k2 assignment could be in a matrix so not recalculated
    // NOTE:  there is no seasonal interpolation, or real age adjustment for age-specific K.  Maybe someday....
                  if(lin_grow(g,ALK_idx,a)==-2.0)
                  {
                    temp=pow(Ave_Size(t,1,g,a),Richards(gp));
                    t2=temp-LinfR;  //  remaining growth potential in transformed units
                    if((a<nages || s<nseas)) Ave_Size(t+1,1,g,k2) =
                      pow((temp+VBK_temp2*t2*Cohort_Growth(y,a)),inv_Richards);
                    if(a==nages && s==nseas) plusgroupsize = pow((temp+VBK_temp2*t2*Cohort_Growth(y,a)),inv_Richards);
                  }
                  else if(lin_grow(g,ALK_idx,a)==-1.0)  // first time point beyond AFIX;  lin_grow will stay at -1 for all remaining subseas of this season
                  {
//                  temp=LminR + (LminR-LinfR)*(mfexp(VBK_temp*seasdur(s)*(real_age(g,ALK_idx2,k2)-AFIX))-1.0)*Cohort_Growth(y,a);
                    temp=LminR + (LminR-LinfR)*(mfexp(VBK_temp*(real_age(g,ALK_idx2,k2)-AFIX)*VBK_seas(s))-1.0)*Cohort_Growth(y,a);
                    Ave_Size(t+1,1,g,k2) = pow(temp,inv_Richards);
                  }
                  else  // in linear phase for subseas
                  {
                    Ave_Size(t+1,1,g,a) = len_bins(1)+lin_grow(g,ALK_idx,a)*(Cohort_Lmin(gp,y,a)-len_bins(1));
                  }
                  
                }  // done ageloop
                break;
              }
              case 8: // Cessation
              {
                for (a=0;a<=nages;a++)
                {
                  k2=a+add_age;  // where add_age =1 if s=nseas, else 0  (k2 assignment could be in a matrix so not recalculated
                  if(a==nages) k2=a;
                  // calculate a full year's growth increment, then multiple by seasdur(s)
                  if(a<nages || s<nseas) Ave_Size(t+1,1,g,k2) =  Ave_Size(t,1,g,a)+
                  (VBK_temp - (VBK_temp/Richards(gp)) * (log(exp(Richards(gp)*(real_age(g,1,a)+1-t50))+1) - log(exp(Richards(gp)*(real_age(g,1,a)-t50))+1)))*seasdur(s); 
                  if(a==nages && s==nseas) plusgroupsize = Ave_Size(t,1,g,nages)+
                  (VBK_temp - (VBK_temp/Richards(gp)) * (log(exp(Richards(gp)*(real_age(g,1,a)+1-t50))+1) - log(exp(Richards(gp)*(real_age(g,1,a)-t50))+1)))*seasdur(s); 
 /*
                  echoinput<<a<<" "<<k2<<" "<<grow_inc<<" lin? "<<lin_grow(g,ALK_idx,a)<<" "<<Cohort_Lmin(gp,y,a)<<endl;
                  if(lin_grow(g,ALK_idx,a)==-2.0)
                  {
                    if((a<nages || s<nseas)) Ave_Size(t+1,1,g,k2) =  Ave_Size(t,1,g,a)+grow_inc*seasdur(s); 
                    if(a==nages && s==nseas) plusgroupsize = Ave_Size(t,1,g,nages)+grow_inc*seasdur(s); 
                  }
                  else if(lin_grow(g,ALK_idx,a)==-1.0)  // first time point beyond AFIX;  lin_grow will stay at -1 for all remaining subseas of this season
                  {
                    Ave_Size(t+1,1,g,k2) = Cohort_Lmin(gp,y,a)+grow_inc*seasdur(s);
                  }
                  else  // in linear phase for subseas
                  {
                    Ave_Size(t+1,1,g,a) = len_bins(1)+lin_grow(g,ALK_idx,a)*(Cohort_Lmin(gp,y,a)-len_bins(1));
                  }
 */
                }  // done ageloop
                break;
              }
              case 5:
                {}
              case 4:
                {}
              case 3:
              {
//  SS_Label_Info_16.2.4.2.1  #standard von Bert growth, loop ages to get size at age at beginning of next season (t+1) which is subseas=1
                for (a=0;a<=nages;a++)
                {
                  if(a<nages) {k2=a+add_age;} else {k2=a;}  // where add_age =1 if s=nseas, else 0  (k2 assignment could be in a matrix so not recalculated
    // NOTE:  there is no seasonal interpolation, or real age adjustment for age-specific K.  Maybe someday....
                  if(lin_grow(g,ALK_idx,a)==-2.0)  //  so doing growth curve
                  {
                    t2=Ave_Size(t,1,g,a)-L_inf(gp);  //  remaining growth potential from first subseas
                    if(timevary_MG(y,2)>0 && t2>-1.)
                    {
                      join1=1.0/(1.0+mfexp(-(50.*t2/(1.0+fabs(t2)))));  //  note the logit transform is not perfect, so growth near Linf will not be exactly same as with native growth function
                      t2*=(1.-join1);  // trap to prevent decrease in size-at-age
                    }

    //  SS_Label_info_16.2.4.2.1.1  #calc size at end of the season, which will be size at begin of next season using current seasons growth parms
                      //  with k2 adding an age if at the end of the year
                    if((a<nages || s<nseas)) Ave_Size(t+1,1,g,k2) = Ave_Size(t,1,g,a) + (mfexp(VBK(gp,a)*seasdur(s)*VBK_seas(s))-1.0)*t2*Cohort_Growth(y,a);
                    if(a==nages && s==nseas) plusgroupsize = Ave_Size(t,1,g,nages) + (mfexp(VBK(gp,nages)*seasdur(s)*VBK_seas(s))-1.0)*t2*Cohort_Growth(y,nages);
                  }
                  else if(lin_grow(g,ALK_idx,a)==-1.0)  // first time point beyond AFIX;  lin_grow will stay at -1 for all remaining subseas of this season
                  {
                    Ave_Size(t+1,1,g,k2) = Cohort_Lmin(gp,y,a) + (Cohort_Lmin(gp,y,a)-L_inf(gp))*
                    (mfexp(VBK(gp,a)*(real_age(g,ALK_idx2,k2)-AFIX)*VBK_seas(s))-1.0)*Cohort_Growth(y,a);
                  }
                  else  // in linear phase
                  {
                    Ave_Size(t+1,1,g,a) = len_bins(1)+lin_grow(g,ALK_idx,a)*(Cohort_Lmin(gp,y,a)-len_bins(1));
                  }
                }  // done ageloop
                break;
              }
            }

//  SS_Label_Info_16.2.4.2.1.2  #after age loop, if(s=nseas) get weighted average for size_at_maxage from carryover fish and fish newly moving into this age
//  this code needs to execute every year, so need to move to ss_popdyn.  Positioned here, it is only updated in years in which growth changes
            if(s==nseas)
            {
              if(y>styr && Linf_decay!=-998.)
                {

//  3.24 code
 #ifdef DO_ONCE
                    if(do_once==1) echoinput<<"  plus group calc: "<<" N _entering: "<<natage(t,1,g,nages-1)<<" N_inplus: "<<natage(t,1,g,nages)<<
                    " size in: "<<Ave_Size(t+1,1,g,nages)<<" old size: "<<plusgroupsize<<" ";
 #endif
                    temp=( (natage(t,1,g,nages-1)+0.01)*Ave_Size(t+1,1,g,nages) + (natage(t,1,g,nages)+0.01)*plusgroupsize) / (natage(t,1,g,nages-1)+natage(t,1,g,nages)+0.02);
                    Ave_Size(t+1,1,g,nages)=temp;
 #ifdef DO_ONCE
                    if(do_once==1&&g==1) echoinput<<"  final_val "<<Ave_Size(t+1,1,g,nages)<<endl;
 #endif
//  early 3.30 code
//                  temp4= square(natage(t,1,g,nages-1)+0.00000001)/(natage(t-1,1,g,nages-2)+0.00000001);
//                  temp=temp4*Ave_Size(t+1,1,g,nages)+(natage(t,1,g,nages)-temp4+0.00000001)*plusgroupsize;
//                  if(do_once==1&&g==1) echoinput<<t<<" plus group calc: "<<" N "<<" "<<natage(t-1,1,g,nages-2)<<" "<<natage(t,1,g,nages-1)<<" "<<natage(t,1,g,nages)<<" T4  "<<temp4<<" N-T4  "<<natage(t,1,g,nages)-temp4+0.00000001<<
//                  " size in: "<<Ave_Size(t+1,1,g,nages)<<" old size: "<<plusgroupsize<<" ";

//  prototype code
//                  temp4= square(natage(t-1,1,g,nages-1)+0.00000001)/(natage(t-2,1,g,nages-2)+0.00000001);
//                  temp2=posfun(natage(t,1,g,nages)-temp4+0.00000001,0.0,temp);
//                  temp=temp4*Ave_Size(t+1,1,g,nages)+(temp2)*plusgroupsize;
//                  if(do_once==1&&g==1) echoinput<<t<<" plus group calc: "<<" N "<<" "<<natage(t-2,1,g,nages-2)<<" "<<natage(t-1,1,g,nages-1)<<" "<<natage(t,1,g,nages)<<" T4  "<<temp4<<" N-T4  "<<natage(t,1,g,nages)-temp4+0.00000001<<
//                  " size in: "<<Ave_Size(t+1,1,g,nages)<<" old size: "<<plusgroupsize<<" ";

//                  Ave_Size(t+1,1,g,nages)=temp/(natage(t,1,g,nages)+0.00000001);
//                  if(do_once==1&&g==1) echoinput<<" temp "<<temp<<" denom "<<(natage(t,1,g,nages)+0.00000001)<<" Z "<<Z_rate(t-1,1,1,nages-1);
                }
                else
                {
                  Ave_Size(t+1,1,g,nages)=Ave_Size(t,1,g,nages);
                }
            }

 #ifdef DO_ONCE
            if(do_once==1) echoinput<<"  seas: "<<s<<"  size@t+1:  "<<Ave_Size(t+1,1,g)(0,min(6,nages))<<" plusgroup: "<<Ave_Size(t+1,1,g,nages)<<endl;
 #endif
           }  // end of season
//  SS_Label_Info_16.2.4.3  #propagate Ave_Size from early years forward until first year that has time-vary growth
          k=y+1;
          j=yz+1;
          while(timevary_MG(j,2)==0 && k<=YrMax)
          {
            for (s=1;s<=nseas;s++)
            {
              t=styr+(k-styr)*nseas+s-1;
              Ave_Size(t,1,g)=Ave_Size(t-nseas,1,g);
              if(s==1 && k<YrMax)
              {
                Ave_Size(t+nseas,1,g)=Ave_Size(t,1,g);  // prep for time-vary next yr
              }
            }  // end season loop
            k++;
            if(j<endyr+1) j++;
          }
        }  // end need to consider this GP x settlement combo (usemorph>0)
      }  // end loop of settlements
      Ip+=N_M_Grow_parms;
    }    // end loop of growth patterns, gp
  } // end do growth

  //  *******************************************************************************************************
  //  SS_Label_Function_16.5  #get_growth3 which calculates mean size-at-age for selected subseason
FUNCTION void get_growth3(const int y, const int t, const int s, const int subseas)
  {
//  progress mean growth through time series, accounting for seasonality and possible change in parameters
//   get mean size at the beginning and end of the season
    dvariable LinfR;
    dvariable LminR;
    dvariable inv_Richards;
    dvariable t50;
    dvariable VBK_temp2;

    ALK_idx=(s-1)*N_subseas+subseas;  //  note that this changes a global value
    for (g=g_Start(1)+N_platoon;g<=gmorph;g+=N_platoon)  // looping the middle platoons for each sex*gp
    {
      if(use_morph(g)>0)
      {
        gp=GP(g);
        switch(Grow_type)
        {
          case 1:  // regular von B
          {
            for (a=0;a<=nages;a++)
            {
    //  SS_Label_Info_16.5.1  #calc subseas size-at-age from begin season size-at-age, accounting for transition from linear to von Bert as necessary
              //  subseasdur is cumulative time to start of this subseas
              if(lin_grow(g,ALK_idx,a)==-2.0)  //  so doing growth curve
              {
                t2=Ave_Size(t,1,g,a)-L_inf(gp);  //  remaining growth potential from first subseas
                                                //  the constant in join needs to be at least 30 to get rapid transition
                                                //   the consequence of (t2>-1.) should be investigated for effect on gradient
                if(timevary_MG(y,2)>0 && t2>-1.)
                {
                  join1=1.0/(1.0+mfexp(-(50.*t2/(1.0+fabs(t2)))));  //  note the logit transform is not perfect, so growth near Linf will not be exactly same as with native growth function
                  t2*=(1.-join1);  // trap to prevent decrease in size-at-age
                }
                Ave_Size(t,subseas,g,a) = Ave_Size(t,1,g,a) + (mfexp(VBK(gp,0)*subseasdur(s,subseas)*VBK_seas(s))-1.0)*t2*Cohort_Growth(y,a);
              }
              else if(lin_grow(g,ALK_idx,a)>=0.0)  // in linear phase for subseas
              {
                Ave_Size(t,subseas,g,a) = len_bins(1)+lin_grow(g,ALK_idx,a)*(Cohort_Lmin(gp,y,a)-len_bins(1));
              }
    // NOTE:  there is no seasonal interpolation, age-specific K uses calendar age, not real age.  Maybe someday....
              else if(lin_grow(g,ALK_idx,a)==-1.0)  // first time point beyond AFIX;  lin_grow will stay at -1 for all remaining subseas of this season
              {
                Ave_Size(t,subseas,g,a) = Cohort_Lmin(gp,y,a) + (Cohort_Lmin(gp,y,a)-L_inf(gp))*
                (mfexp(VBK(gp,0)*(real_age(g,ALK_idx,a)-AFIX)*VBK_seas(s))-1.0)*Cohort_Growth(y,a);
              }
            }
            break;
          }
          case 2:  //  Richards
          {
            LinfR=pow(L_inf(gp),Richards(gp));
            LminR=pow(Lmin(gp),Richards(gp));
            inv_Richards=1.0/Richards(gp);
            //  uses VBK(nages) because age-specific K not allowed
           //  and Cohort_Lmin has already had the power function applied
            for (a=0;a<=nages;a++)
            {
              if(lin_grow(g,ALK_idx,a)==-2.0)   //  so doing growth curve
              {
                temp=pow(Ave_Size(t,1,g,a),Richards(gp));
                t2=temp-LinfR;  //  remaining growth potential
  //              disable the shrinkage trap because Richard's parameter could be negative
  //              join1=1.0/(1.0+mfexp(-(50.*t2/(1.0+fabs(t2)))));  //  note the logit transform is not perfect, so growth near Linf will not be exactly same as with native growth function
  //              t2*=(1.-join1);  // trap to prevent decrease in size-at-age
                temp += (mfexp(VBK(gp,0)*subseasdur(s,subseas)*VBK_seas(s))-1.0)*t2*Cohort_Growth(y,a);
                Ave_Size(t,subseas,g,a) = pow(temp,inv_Richards);
              }
              else if(lin_grow(g,ALK_idx,a)>=0.0)  // in linear phase for subseas
              {
                Ave_Size(t,subseas,g,a) = len_bins(1)+lin_grow(g,ALK_idx,a)*(Cohort_Lmin(gp,y,a)-len_bins(1));
              }
              else if(lin_grow(g,ALK_idx,a)==-1.0)  // first time point beyond AFIX;  lin_grow will stay at -1 for all remaining subseas of this season
              {
  //              temp=Cohort_Lmin(gp,y,a) + (Cohort_Lmin(gp,y,a)-LinfR)*
                temp=LminR + (LminR-LinfR)*
                (mfexp(VBK(gp,0)*(real_age(g,ALK_idx,a)-AFIX)*VBK_seas(s))-1.0)*Cohort_Growth(y,a);
                Ave_Size(t,subseas,g,a) = pow(temp,inv_Richards);
              }
            }  // done ageloop
            break;
          }  //  done Richards
          case 8: // Cessation
          {
  //                VBK_temp2=-VBK_temp*seasdur(s);  //  negative to restore positive
            // t50 is the calculated inflection age for the decline in K
            dvariable VBK_temp=-VBK(gp,0);
            t50=log(exp((L_inf(gp)-Lmin(gp))*Richards(gp)/(VBK_temp))-1.0)/Richards(gp);
            for (a=0;a<=nages;a++)
            {
              // calculate a full year's growth increment, then multiple by seasdur(s)
              Ave_Size(t,subseas,g,a) = Ave_Size(t,1,g,a) +
              (VBK_temp - (VBK_temp/Richards(gp)) * (log(exp(Richards(gp)*(real_age(g,ALK_idx,a)+1-t50))+1) - log(exp(Richards(gp)*(real_age(g,ALK_idx,a)-t50))+1)))*subseasdur(s,subseas); 
            }  // done ageloop
            break;
          }
          case 5:  // von B with age-specific K
            {}
          case 4:  // von B with age-specific K
            {}
          case 3:  // von B with age-specific K
          {
            for (a=0;a<=nages;a++)
            {
    //  SS_Label_Info_16.5.1  #calc subseas size-at-age from begin season size-at-age, accounting for transition from linear to von Bert as necessary
              //  subseasdur is cumulative time to start of this subseas
              if(lin_grow(g,ALK_idx,a)==-2.0)   //  so doing growth curve
              {
                t2=Ave_Size(t,1,g,a)-L_inf(gp);  //  remaining growth potential from first subseas
                                                //  the constant in join needs to be at least 30 to get rapid transition
                                                //   the consequence of (t2>-1.) should be investigated for effect on gradient
                if(timevary_MG(y,2)>0 && t2>-1.)
                {
                  join1=1.0/(1.0+mfexp(-(50.*t2/(1.0+fabs(t2)))));  //  note the logit transform is not perfect, so growth near Linf will not be exactly same as with native growth function
                  t2*=(1.-join1);  // trap to prevent decrease in size-at-age
                }
                Ave_Size(t,subseas,g,a) = Ave_Size(t,1,g,a) + (mfexp(VBK(gp,a)*subseasdur(s,subseas)*VBK_seas(s))-1.0)*t2*Cohort_Growth(y,a);
              }
              else if(lin_grow(g,ALK_idx,a)>=0.0)  // in linear phase for subseas
              {
                Ave_Size(t,subseas,g,a) = len_bins(1)+lin_grow(g,ALK_idx,a)*(Cohort_Lmin(gp,y,a)-len_bins(1));
              }
    // NOTE:  there is no seasonal interpolation, age-specific K uses calendar age, not real age.  Maybe someday....
              else if(lin_grow(g,ALK_idx,a)==-1.0)  // first time point beyond AFIX;  lin_grow will stay at -1 for all remaining subseas of this season
              {
                Ave_Size(t,subseas,g,a) = Cohort_Lmin(gp,y,a) + (Cohort_Lmin(gp,y,a)-L_inf(gp))*
                (mfexp(VBK(gp,a)*(real_age(g,ALK_idx,a)-AFIX)*VBK_seas(s))-1.0)*Cohort_Growth(y,a);
              }
            }
            break;
          }
        }  //  done switch
      }  //  end need this platoon
    }  //  done platoon
  }  //  end  calc size-at-age at a particular subseason


FUNCTION void get_natmort()
  {
  //  SS_Label_Function #17 get_natmort
  dvariable Loren_M1;
  dvariable Loren_temp;
  dvariable Loren_temp2;
  dvariable t_age;
  int gpi;
  int Do_AveAge;
  int K_index;
  K_index=VBK(1).indexmax();
  Do_AveAge=0;
  t_base=styr+(yz-styr)*nseas-1;
  Ip=-N_M_Grow_parms;   // start counter for MGparms
  //  SS_Label_Info_17.1  #loop growth patterns in each gender
  gp=0;
  for (gg=1;gg<=gender;gg++)
  for (GPat=1;GPat<=N_GP;GPat++)
  {
    gp++;
    Ip=MGparm_point(gg,GPat)-1;
  	if(N_natMparms>0)
  	{
  //  SS_Label_Info_17.1.1 #Copy parameter values from mgp_adj to natMparms(gp), doing direct or offset for gp>1
    for (j=1;j<=N_natMparms;j++) {natMparms(j,gp)=mgp_adj(Ip+j);}
    switch(MGparm_def)   //  switch for natmort parms
    {
      case 1:  // direct
      {
      	for (j=1;j<=N_natMparms;j++)
      	{
      		if(natMparms(j,gp)<0) natMparms(j,gp)=natMparms(j,1);
      	}
        break;
      }
      case 2:  // offset
      {
        if(gp>1)
        {
          for (j=1;j<=N_natMparms;j++)
          {
            natMparms(j,gp)=natMparms(j,1)*mfexp(natMparms(j,gp));
          }
        }
        break;
      }
      case 3:  // offset like SS2 V1.23
      {
          if(gp>1) natMparms(1,gp)=natMparms(1,1)*mfexp(natMparms(1,gp));
          if(N_natMparms>1)
          {
          for (j=2;j<=N_natMparms;j++)
          {
            natMparms(j,gp)=natMparms(j-1,gp)*mfexp(natMparms(j,gp));
          }
        }
        break;
      }
    }  // end switch
    }  // end have natmort parms

    g=g_Start(gp);  //  base platoon
    for (settle=1;settle<=N_settle_timings;settle++)
    {
  //  SS_Label_Info_17.1.2  #loop settlements
      g+=N_platoon;
      gpi=GP3(g);   // GP*gender*settlement
      if(use_morph(g)>0)
      {
        switch(natM_type)
        {
  //  SS_Label_Info_17.1.2.0  #case 0:  constant M
          case 0:  // constant M
          {
            for (s=1;s<=nseas;s++)
            {
              if(docheckup==1) echoinput<<"Natmort "<<s<<" "<<gp<<" "<<gpi<<" "<<natMparms(1,gp);
              natM(s,gpi)=natMparms(1,gp);
              surv1(s,gpi)=mfexp(-natMparms(1,gp)*seasdur_half(s));   // refers directly to the constant value
              surv2(s,gpi)=square(surv1(s,gpi));
              if(docheckup==1) echoinput<<" surv "<<surv1(s,gpi)<<endl;
            }
            break;
          }

  //  SS_Label_Info_17.1.2.1  #case 1:  N breakpoints
          case 1:  // breakpoints
          {
            dvariable natM1;
            dvariable natM2;
            for (s=1;s<=nseas;s++)
            {
              if(s>=Bseas(g))
              {a=0; t_age=azero_seas(s)-azero_G(g);}
              else
              {a=1; t_age=1.0+azero_seas(s)-azero_G(g);}
              natM_amax=NatM_break(1);
              natM2=natMparms(1,gp);
              k=a;

              for (loop=1;loop<=N_natMparms+1;loop++)
              {
                natM_amin=natM_amax;
                natM1=natM2;
                if(loop<=N_natMparms)
                {
                  natM_amax=NatM_break(loop);
                  natM2=natMparms(loop,gp);
                }
                else
                {
                  natM_amax=r_ages(nages)+1.;
                }
                if(natM_amax>natM_amin)
                {temp=(natM2-natM1)/(natM_amax-natM_amin);}  //  calc the slope
                else
                {temp=0.0;}
                while(t_age<natM_amax && a<=nages)
                {
                  natM(s,gpi,a)=natM1+(t_age-natM_amin)*temp;
                  t_age+=1.0; a++;
                }
              }
              if(k==1) natM(s,gpi,0)=natM(s,gpi,1);
              surv1(s,gpi)=mfexp(-natM(s,gpi)*seasdur_half(s));
              surv2(s,gpi)=square(surv1(s,gpi));
            } // end season
            break;
          }  // end natM_type==1

  //  SS_Label_Info_17.1.2.2  #case 2:  lorenzen M
          case 2:  //  Lorenzen M
          {
            Loren_temp2=L_inf(gp)*(mfexp(-VBK(gp,K_index)*VBK_seas(0))-1.);   // need to verify use of VBK_seas here
            int Loren_t=styr+(yz-styr)*nseas+Bseas(g)-1;
            Loren_temp=Ave_Size(styr,mid_subseas,g,int(natM_amin));  // uses mean size in middle of season 1 for the reference age
            Loren_M1=natMparms(1,gp)/log(Loren_temp/(Loren_temp+Loren_temp2));
            for (s=nseas;s>=1;s--)
            {
//              ALK_idx=(s-1)*N_subseas+mid_subseas;  //  for midseason
              for (a=nages; a>=0;a--)
              {
                if(a==0 && s<Bseas(g))
                {natM(s,gpi,a)=natM(s+1,gpi,a);}
                else
//                {natM(s,gpi,a)=log(Ave_Size(t,ALK_idx,g,a)/(Ave_Size(t,ALK_idx,g,a)+Loren_temp2))*Loren_M1;}
                {natM(s,gpi,a)=log(Ave_Size(Loren_t,mid_subseas,g,a)/(Ave_Size(Loren_t,mid_subseas,g,a)+Loren_temp2))*Loren_M1;}
                surv1(s,gpi,a)=mfexp(-natM(s,gpi,a)*seasdur_half(s));
                surv2(s,gpi,a)=square(surv1(s,gpi,a));
              }   // end age loop
            }
            break;
          }
  //  SS_Label_Info_17.1.2.3  #case 3:  set to empirical M as read from file, no seasonal interpolation
          case(3):   // read age_natmort as constant
          {
            for (s=1;s<=nseas;s++)
            {
              natM(s,gpi)=Age_NatMort(gp);
              surv1(s,gpi)=value(mfexp(-natM(s,gpi)*seasdur_half(s)));
              surv2(s,gpi)=value(square(surv1(s,gpi)));
            }
            break;
          }

  //  SS_Label_Info_17.1.2.4  #case 4:  read age_natmort as constant and interpolate to seasonal real age
          case(4):
          {
            for (s=1;s<=nseas;s++)
            {
              if(s>=Bseas(g))
              {
                k=0; t_age=azero_seas(s)-azero_G(g);
                for (a=k;a<=nages-1;a++)
                {
                  natM(s,gpi,a) = Age_NatMort(gp,a)+t_age*(Age_NatMort(gp,a+1)-Age_NatMort(gp,a));
                } // end age
              }
              else
              {
                k=1; t_age=azero_seas(s)+(1.-azero_G(g));
                for (a=k;a<=nages-1;a++)
                {
                  natM(s,gpi,a) = Age_NatMort(gp,a)+t_age*(Age_NatMort(gp,a+1)-Age_NatMort(gp,a));
                } // end age
                natM(s,gpi,0)=natM(s,gpi,1);
              }
              natM(s,gpi,nages)=Age_NatMort(gp,nages);
              surv1(s,gpi)=mfexp(-natM(s,gpi)*seasdur_half(s));
              surv2(s,gpi)=square(surv1(s,gpi));
            } // end season
            break;
          }
        }  // end natM_type switch

  //  SS_Label_Info_17.2  #calc an ave_age for the first gp as a scaling factor in logL for initial recruitment (R1) deviation
        if(Do_AveAge==0)
        {
          Do_AveAge=1;
          ave_age = 1.0/natM(1,gpi,nages/2)-0.5;
        }
 #ifdef DO_ONCE
        if(do_once==1)
        {
         for(s=1;s<=nseas;s++) echoinput<<"Natmort seas:"<<s<<" sex:"<<gg<<" Gpat:"<<GPat<<" sex*Gpat:"<<gp<<" settlement:"<<settle<<" gpi:"<<gpi<<" M: "<<natM(s,gpi)<<endl;
        }
 #endif
      } //  end use of this morph
    } // end settlement
  }   // end growth pattern x gender loop
  } // end nat mort

FUNCTION void get_recr_distribution()
  {
 /*  SS_Label_Function_18 #get_recr_distribution among areas and morphs */

//  SS_Label_Info_18.15  #get fraction female
// fracfemale_mult is not used to distribute recruits; it is a multiplier used in the SSB calc and has default value of 1, and value of femfrac if requested in 1 sex setup
  if (frac_female_pointer > 0)
  {
      Ip = frac_female_pointer - 1;
      for (gp=1;gp<=N_GP;gp++)
      {
        femfrac(gp) = mgp_adj(Ip + gp);
        if(gender==2) femfrac(N_GP+gp) = 1.0 - femfrac(gp);
      }
  }
  else
  {
    femfrac(1,N_GP)=fracfemale;
    if(gender==2) femfrac(N_GP,2*N_GP)=1.0-fracfemale;
  }
  if(gender_rd==-1) 
    {
      fracfemale_mult=value(femfrac(1));
    }
  
 #ifdef DO_ONCE
  if(do_once==1)  echoinput<<" femfrac "<<femfrac<<endl;
 #endif
  if(finish_starter==999)
  {k=MGP_CGD-recr_dist_parms+nseas;}
  else
  {k=MGP_CGD-recr_dist_parms;}
  dvar_vector recr_dist_parm(1,k);

//  recr_dist.initialize();
//  SS_Label_Info_18.1  #set rec_dist_parms = exp(mgp_adj) for this year
  Ip=recr_dist_parms-1;
  for (f=1;f<=MGP_CGD-recr_dist_parms;f++)
  {
    recr_dist_parm(f)=mfexp(mgp_adj(Ip+f));
  }
//  SS_Label_Info_18.2  #loop gp * settlements * area and multiply together the recr_dist_parm values
  switch(recr_dist_method)
  {
    
  case 2:
  {
    for (gp=1;gp<=N_GP;gp++)
    for (settle=1;settle<=N_settle_timings;settle++)
    for (p=1;p<=pop;p++)
    if(recr_dist_pattern(gp,settle,p)>0)
    {
      recr_dist(y,gp,settle,p)=femfrac(gp)*recr_dist_parm(gp)*recr_dist_parm(N_GP+p)*recr_dist_parm(N_GP+pop+settle);
      if(gender==2) recr_dist(y,gp+N_GP,settle,p)=femfrac(gp+N_GP)*recr_dist_parm(gp)*recr_dist_parm(N_GP+p)*recr_dist_parm(N_GP+pop+settle);  //males
    }
  //  SS_Label_Info_18.3  #if recr_dist_interaction is chosen, then multiply these in also
    if(recr_dist_inx==1)
    {
      f=N_GP+pop+N_settle_timings;
      for (gp=1;gp<=N_GP;gp++)
      for (settle=1;settle<=N_settle_timings;settle++)
      for (p=1;p<=pop;p++)
      {
        f++;
        if(recr_dist_pattern(gp,settle,p)>0)
        {
          recr_dist(y,gp,settle,p)*=recr_dist_parm(f);
          if(gender==2) recr_dist(y,gp+N_GP,settle,p)*=recr_dist_parm(f);
        }
      }
    }
    break;
  }
  case 3:
  {
    for (settle=1;settle<=N_settle_assignments;settle++)
    {
      gp=settlement_pattern_rd(settle,1);
      settle_time=settle_assignments_timing(settle);
      p=settlement_pattern_rd(settle,3);
      recr_dist(y,gp,settle_time,p)=femfrac(gp)*recr_dist_parm(settle);
      if(gender==2) recr_dist(y,gp+N_GP,settle_time,p)=femfrac(gp+N_GP)*recr_dist_parm(settle);  //males
    }
    break;
  }
  case 4:
  {
    recr_dist(y,1,1,1)=femfrac(1);
    if(gender==2) recr_dist(y,2,1,1)=femfrac(2);
    break;
  }
  case 1:  //  only used for sstrans
  {
    for (gp=1;gp<=N_GP;gp++)
    for (p=1;p<=pop;p++)
    for (s=1;s<=N_settle_timings;s++)
    {
    if(recr_dist_pattern(gp,s,p)>0)
    {
      recr_dist(y,gp,s,p)=femfrac(gp)*recr_dist_parm(gp)*recr_dist_parm(N_GP+p)*recr_dist_parm(N_GP+pop+s);
      if(gender==2) recr_dist(y,gp+N_GP,s,p)=femfrac(gp+N_GP)*recr_dist_parm(gp)*recr_dist_parm(N_GP+p)*recr_dist_parm(N_GP+pop+s);  //males
    }
    }
  //  SS_Label_Info_18.3  #if recr_dist_interaction is chosen, then multiply these in also
    if(recr_dist_inx==1)
    {
      f=N_GP+nseas+pop;
      for (gp=1;gp<=N_GP;gp++)
      for (p=1;p<=pop;p++)
      for (s=1;s<=N_settle_timings;s++)
      {
        f++;
        if(recr_dist_pattern(gp,s,p)>0)
        {
          recr_dist(y,gp,s,p)*=recr_dist_parm(f);
          if(gender==2) recr_dist(y,gp+N_GP,s,p)*=recr_dist_parm(f);
        }
      }
    }
    break;
  }
  }
//  SS_Label_Info_18.4  #scale the recr_dist matrix to sum to 1.0
  recr_dist(y)/=sum(recr_dist(y));

  if(y==styr)
 	{for(int yz=styr+1; yz<=YrMax;yz++) recr_dist(yz)=recr_dist(styr);}
  
 #ifdef DO_ONCE
    if(do_once==1) 
      {
        echoinput<<"recruitment distribution in year: "<<y<<endl<<"GP Seas Area Use? female_recr_dist"<<endl;
      for (gp=1;gp<=N_GP;gp++)
      for (s=1;s<=N_settle_timings;s++)
      for (p=1;p<=pop;p++)
      {echoinput<<gp<<" "<<s<<" "<<p<<" "<<recr_dist_pattern(gp,s,p)<<" "<<recr_dist(y,gp,s,p);
        echoinput<<endl;
        }
     }
 #endif
  }

//*******************************************************************
 /*  SS_Label_Function 19 get_wtlen, maturity, fecundity, hermaphroditism */
FUNCTION void get_wtlen()
  {
//  SS_Label_Info_19.1  #set wtlen and maturity/fecundity factors equal to annual values from mgp_adj
  gp=0;
  for (gg=1;gg<=gender;gg++)
  for (GPat=1;GPat<=N_GP;GPat++)
  {
    gp++;
    if(gg==1)
    {
      for(f=1;f<=6;f++) {wtlen_p(GPat,f)=mgp_adj(MGparm_point(gg,GPat)+N_M_Grow_parms+f-1);}
    }
    else
    {
      for(f=7;f<=8;f++) {wtlen_p(GPat,f)=mgp_adj(MGparm_point(gg,GPat)+N_M_Grow_parms+(f-6)-1);}
    }
//    if(do_once==1) echoinput<<"get wtlen parms sex: "<<gg<<" Gpat: "<<GPat<<" sex*Gpat: "<<gp<<" "<<wtlen_p(GPat)<<endl;

    for (s=1;s<=nseas;s++)
    {
//  SS_Label_Info_19.2  #loop seasons for wt-len calc
      t=styr+(y-styr)*nseas+s-1;
//  SS_Label_Info_19.2.1  #calc wt_at_length for each season to include seasonal effects on wtlen

//  NOTES  wt_len is by gp, but wt_len2 and wt_len_low have males stacked after females
//  so referenced by GPat

      if(gg==1)
      {
      if(MGparm_seas_effects(1)>0 || MGparm_seas_effects(2)>0 )        //  get seasonal effect on FEMALE wtlen parameters
      {
        wt_len(s,gp)=(wtlen_p(GPat,1)*wtlen_seas(s,GPat,1))*pow(len_bins_m(1,nlength),(wtlen_p(GPat,2)*wtlen_seas(s,GPat,2)));
        wt_len_low(s,GPat)(1,nlength)=(wtlen_p(GPat,1)*wtlen_seas(s,GPat,1))*pow(len_bins2(1,nlength),(wtlen_p(GPat,2)*wtlen_seas(s,GPat,2)));
      }
      else
      {
        wt_len(s,gp) = wtlen_p(GPat,1)*pow(len_bins_m(1,nlength),wtlen_p(GPat,2));
        wt_len_low(s,GPat)(1,nlength) = wtlen_p(GPat,1)*pow(len_bins2(1,nlength),wtlen_p(GPat,2));
      }
      wt_len2(s,GPat)(1,nlength)=wt_len(s,gp)(1,nlength);
      }
//  SS_Label_Info_19.2.2  #calculate male weight_at_length
      else
      {
        if(MGparm_seas_effects(7)>0 || MGparm_seas_effects(8)>0 )        //  get seasonal effect on male wt-len parameters
        {
          wt_len(s,gp) = (wtlen_p(GPat,7)*wtlen_seas(s,GPat,7))*pow(len_bins_m(1,nlength),(wtlen_p(GPat,8)*wtlen_seas(s,GPat,8)));
          wt_len_low(s,GPat)(nlength1,nlength2) = (wtlen_p(GPat,7)*wtlen_seas(s,GPat,7))*pow(len_bins2(nlength1,nlength2),(wtlen_p(GPat,8)*wtlen_seas(s,GPat,8)));
        }
        else
        {
          wt_len(s,gp) = wtlen_p(GPat,7)*pow(len_bins_m(1,nlength),wtlen_p(GPat,8));
          wt_len_low(s,GPat)(nlength1,nlength2) = wtlen_p(GPat,7)*pow(len_bins2(nlength1,nlength2),wtlen_p(GPat,8));
        }
        wt_len2(s,GPat)(nlength1,nlength2)=wt_len(s,gp).shift(nlength1);
        wt_len(s,gp).shift(1);
      }

//  SS_Label_Info_19.2.3  #calculate first diff of wt_len for use in generalized sizp comp bin calculations
      if(gg==gender)
      {
        wt_len2_sq(s,GPat)=elem_prod(wt_len2(s,GPat),wt_len2(s,GPat));
        wt_len_fd(s,GPat)=first_difference(wt_len_low(s,GPat));
        if(gender==2) wt_len_fd(s,GPat,nlength)=wt_len_fd(s,GPat,nlength-1);
 #ifdef DO_ONCE
          if(do_once==1) echoinput<<"wtlen2 "<<endl<<wt_len2<<endl<<"wtlen2^2 "<<wt_len2_sq<<endl<<"wtlen2:firstdiff "<<wt_len_fd<<endl;
 #endif
      }
  //  SS_Label_Info_19.2.4  #calculate maturity and fecundity if seas = spawn_seas
  //  these calculations are done in spawn_seas, but are not affected by spawn_time within that season
  //  so age-specific inputs will assume to be at correct timing already; size-specific will later be adjusted to use size-at-age at the exact correct spawn_time_seas
//  SPAWN-RECR:   calculate maturity and fecundity vectors

      if(s==spawn_seas && gg==1)  // get biology of maturity and fecundity
      {
 #ifdef DO_ONCE
         if(do_once==1) echoinput<<"process maturity fecundity using option: "<<Maturity_Option<<endl;
 #endif
          switch(Maturity_Option)
          {
            case 1:  //  Maturity_Option=1  length logistic
            {
              mat_len(gp) = 1./(1. + mfexp(wtlen_p(GPat,4)*(len_bins_m(1,nlength)-wtlen_p(GPat,3))));
              break;
            }
            case 2:  //  Maturity_Option=2  age logistic
            {
              mat_age(gp) = 1./(1. + mfexp(wtlen_p(GPat,4)*(r_ages-wtlen_p(GPat,3))));
              break;
            }
            case 3:  //  Maturity_Option=3  read age-maturity
            {
              mat_age(gp)=Age_Maturity(gp);
              break;
            }
            case 4:  //  Maturity_Option=4   read age-fecundity, so no age-maturity
            {
              break;
            }
            case 5:  //  Maturity_Option=5   read age-fecundity from wtatage.ss
            {
              break;
            }
            case 6:  //  Maturity_Option=6   read length-maturity
            {
              mat_len(gp)=Length_Maturity(gp);
              break;
            }
          }
 #ifdef DO_ONCE
           if(do_once==1) echoinput<<"gp: "<<GPat<<" matlen: "<<mat_len(gp)<<endl;
           if(do_once==1) echoinput<<"gp: "<<GPat<<" matage: "<<mat_age(gp)<<endl;
 #endif
          if(First_Mature_Age>0)
          {mat_age(gp)(0,First_Mature_Age-1)=0.;}

          switch (Fecund_Option)
          {
            case 1:    // as eggs/kg (SS original configuration)
            {
              fec_len(gp) = wtlen_p(GPat,5)+wtlen_p(GPat,6)*wt_len(s,gp);
              fec_len(gp) = elem_prod(wt_len(s,gp),fec_len(gp));
              break;
            }
            case 2:
            {       // as eggs = f(length)
              fec_len(gp) = wtlen_p(GPat,5)*pow(len_bins_m,wtlen_p(GPat,6));
              break;
            }
            case 3:
            {       // as eggs = f(body weight)
              fec_len(gp) = wtlen_p(GPat,5)*pow(wt_len(s,gp),wtlen_p(GPat,6));
              break;
            }
            case 4:
            {       // as eggs = a + b*Len
              fec_len(gp) = wtlen_p(GPat,5) + wtlen_p(GPat,6)*len_bins_m;
              if(wtlen_p(GPat,5)<0.0)
              {
                z=1;
                while(fec_len(gp,z)<0.0)
                {
                  fec_len(gp,z)=0.0;
                  z++;
                }
              }
              break;
            }
            case 5:
            {       // as eggs = a + b*Wt
              fec_len(gp) = wtlen_p(GPat,5) + wtlen_p(GPat,6)*wt_len(s,gp);
              if(wtlen_p(GPat,5)<0.0)
              {
                z=1;
                while(fec_len(gp,z)<0.0)
                {
                  fec_len(gp,z)=0.0;
                  z++;
                }
              }
              break;
            }
          }
// 1=length logistic; 2=age logistic; 3=read age-maturity
// 4= read age-fecundity by growth_pattern 5=read all from separate wtatage.ss file
//  6=read length-maturity
     if(Maturity_Option!=4 && Maturity_Option!=5)
     {
  //  combine length maturity and fecundity; but will be ignored if reading empirical age-fecundity
       mat_fec_len(gp) = elem_prod(mat_len(gp),fec_len(gp));
 #ifdef DO_ONCE
       if(do_once==1) echoinput<<"mat_fec_len "<<endl<<mat_fec_len(gp)<<endl;
 #endif
     }
 #ifdef DO_ONCE
     else if(Maturity_Option==4)
      {
        if(do_once==1) echoinput<<"age-fecundity as read from control file"<<endl<<Age_Maturity(gp)<<endl;
      }
      else
     {
        if(do_once==1) echoinput<<"age-fecundity read from wtatage.ss"<<endl;
     }
 #endif
    }
    }  // end season loop
  }  // end GP loop
//  end wt-len and fecundity

//  SS_Label_Info_19.2.5  #Do Hermaphroditism (no seasonality and no gp differences)
//  should build seasonally component here
//  only one hermaphroditism definition is allowed (3 parameters), but it is stored by Gpat, so referenced by GP4(g)
    if(Hermaphro_Option!=0)
    {
      dvariable infl;  // inflection
      dvariable stdev;  // standard deviation
      dvariable maxval;  // max value

      infl=mgp_adj(MGparm_Hermaphro);  // inflection
      stdev=mgp_adj(MGparm_Hermaphro+1);  // standard deviation
      maxval=mgp_adj(MGparm_Hermaphro+2);  // max value
//      minval is 0.0;
      temp2=cumd_norm((0.0-infl)/stdev);     //  cum_norm at age 0
      temp=maxval / (cumd_norm((r_ages(nages)-infl)/stdev)-temp2);   //  delta in cum_norm between styr and endyr
      for (a=0; a<=nages; a++)
      {
        Hermaphro_val(1,a)=0.0 + temp * (cumd_norm((r_ages(a)-infl)/stdev)-temp2);
      }
      if(N_GP>1)
        for(gp=2;gp<=N_GP;gp++)
        {
          Hermaphro_val(gp)=Hermaphro_val(1);
        }
    }

  }

FUNCTION void get_migration()
  {
//*******************************************************************
//  SS_Label_FUNCTION 20 #get_migration
  Ip=MGP_CGD;   // base counter for  movement parms
//  SS_Label_20.1  loop the needed movement rates
  for (k=1;k<=do_migr2;k++)   //  loop all movement rates for this year (includes seas, morphs)
  {
    t=styr+(yz-styr)*nseas+move_def2(k,1)-1;
    if(k<=do_migration) //  so an explicit movement rate
    {
//  set some movement rates same as the first movement rate
      if(mgp_adj(Ip+1)==-9999.) mgp_adj(Ip+1)=mgp_adj(MGP_CGD+1);
      if(mgp_adj(Ip+2)==-9999.) mgp_adj(Ip+2)=mgp_adj(MGP_CGD+2);
//  set movement rate same for all ages
      if(mgp_adj(Ip+2)==-9998.) mgp_adj(Ip+2)=mgp_adj(Ip+1);

//  SS_Label_Info_20.1.1  #age-specific movement strength based on parameters for selected area pairs
      temp=1./(move_def2(k,6)-move_def2(k,5));
      temp1=temp*(mgp_adj(Ip+2)-mgp_adj(Ip+1));
      for (a=0;a<=nages;a++)
      {
        if(a<=move_def2(k,5)) {migrrate(yz,k,a) = mgp_adj(Ip+1);}
        else if(a>=move_def2(k,6)) {migrrate(yz,k,a) = mgp_adj(Ip+2);}
        else {migrrate(yz,k,a) = mgp_adj(Ip+1) + (r_ages(a)-move_def2(k,5))*temp1;}
      }   // end age loop
      migrrate(yz,k)=mfexp(migrrate(yz,k));
      Ip+=2;
    }
    else
//  SS_Label_Info_20.1.2  #default movement strength =1.0 for other area pairs
    {
      migrrate(yz,k)=1.;
    }
  }

//  SS_Label_Info_20.2  #loop seasons, GP, source areas
  for (s=1;s<=nseas;s++)
  {
    t=styr+(yz-styr)*nseas+s-1;
    for (gp=1;gp<=N_GP;gp++)
    {
      for (p=1;p<=pop;p++)
      {
        tempvec_a.initialize();   // zero out the summation vector
        for (p2=1;p2<=pop;p2++)
        {
//  SS_Label_Info_20.2.1  #for each destination area, adjust movement rate by season duration and sum across all destination areas
          k=move_pattern(s,gp,p,p2);
          if(k>0)
          {
            if(p2!=p && nseas>1) migrrate(yz,k)*=seasdur(move_def2(k,1));  // fraction leaving an area is reduced if the season is short
            tempvec_a+=migrrate(yz,k);          //  sum of all movement weights for the p2 fish
          }
        }   //end destination area
//  SS_Label_Info_20.2.2 #now normalize for all movement from source area p
        for (p2=1;p2<=pop;p2++)
        {
          k=move_pattern(s,gp,p,p2);
          if(k>0)
          {
            migrrate(yz,k)=elem_div(migrrate(yz,k),tempvec_a);
  //  SS_Label_Info_20.2.3 #Set rate to 0.0 (or 1.0 for stay rates) below the start age for migration
            if(migr_start(s,gp)>0)
            {
              if(p!=p2)
              {
                migrrate(yz,k)(0,migr_start(s,gp)-1)=0.0;
              }
              else
              {
                migrrate(yz,k)(0,migr_start(s,gp)-1)=1.0;
              }
            }
          }
        }
      }    //  end source areas loop
    }  // end growth pattern
  }  // end season

  //  SS_Label_Info_20.2.4 #Copy annual migration rates forward until first year with time-varying migration rates
  if(yz<endyr)
  {
    k=yz+1;
    while(timevary_MG(k,5)==0 && k<=endyr)
    {
      migrrate(k)=migrrate(k-1);  k++;
    }
  }
//  end migration
  }

FUNCTION void get_migration2()
  {
//*******************************************************************
//  SS_Label_FUNCTION 20 #get_migration
//  for use with new movement approach
//  each defined movedef rate (1 to do_migr2) has a min age, max age, functional form
//  each move_pattern(GP, sex, settlement, seas, source, sink) selects rate it uses
//  so all could point to just 1 rate definition, or a complex setup could be created
//  to ease creation of setups of moderate complexity, use 0 to select all of that dimension
//  for example, 0 in the sex field would assign the specified rate to both sexes
//  for example, 0 in all fields would assign the same rate to everything

  Ip=MGP_CGD;   // base counter for  movement parms
  dvariable move1;  //  movement rate for young fish
  dvariable move2;  //  movement rate for old fish
  
//  SS_Label_20.1  loop the needed movement rates
  for (k=1;k<=do_migr2;k++)   //  loop all movement rates for this year (includes seas, morphs)
  {
//  seems not used    t=styr+(yz-styr)*nseas+move_def2(k,1)-1;
    if(k<=do_migration) //  so an explicit movement rate
    {
//  set some movement rates same as the first movement rate
      move1=mgp_adj(Ip+1);
      if(mgp_adj(Ip+1)==-9999.) move1=mgp_adj(MGP_CGD+1);
      move2=mgp_adj(Ip+1);
      if(mgp_adj(Ip+2)==-9999.) move2=mgp_adj(MGP_CGD+2);
//  set movement rate same for all ages
      if(mgp_adj(Ip+2)==-9998.) move2=move1;

//  SS_Label_Info_20.1.1  #age-specific movement strength based on parameters for selected area pairs
      temp=1./(move_def2(k,6)-move_def2(k,5));
      temp1=temp*(move2-move1);
      migrrate(yz,k)=move1 + (r_ages-move_def2(k,5))*temp1;
      migrrate(yz,k)(0,move_def2(k,5))=move1;
      migrrate(yz,k)(move_def2(k,5),nages)=move2;
      migrrate(yz,k)=mfexp(migrrate(yz,k));
      Ip+=2;
    }
    else
//  SS_Label_Info_20.1.2  #default movement strength =1.0 for other area pairs
    {
      migrrate(yz,k)=1.;
    }
  }

//  SS_Label_Info_20.2  #loop seasons, GP, source areas
  for (s=1;s<=nseas;s++)
  {
    t=styr+(yz-styr)*nseas+s-1;
    for (gp=1;gp<=N_GP;gp++)
    {
      for (p=1;p<=pop;p++)
      {
        tempvec_a.initialize();   // zero out the summation vector
        for (p2=1;p2<=pop;p2++)
        {
//  SS_Label_Info_20.2.1  #for each destination area, adjust movement rate by season duration and sum across all destination areas
          k=move_pattern(s,gp,p,p2);
          if(k>0)
          {
            if(p2!=p && nseas>1) migrrate(yz,k)*=seasdur(move_def2(k,1));  // fraction leaving an area is reduced if the season is short
            tempvec_a+=migrrate(yz,k);          //  sum of all movement weights for the p2 fish
          }
        }   //end destination area
//  SS_Label_Info_20.2.2 #now normalize for all movement from source area p
        for (p2=1;p2<=pop;p2++)
        {
          k=move_pattern(s,gp,p,p2);
          if(k>0)
          {
            migrrate(yz,k)=elem_div(migrrate(yz,k),tempvec_a);
  //  SS_Label_Info_20.2.3 #Set rate to 0.0 (or 1.0 for stay rates) below the start age for migration
            if(migr_start(s,gp)>0)
            {
              if(p!=p2)
              {
                migrrate(yz,k)(0,migr_start(s,gp)-1)=0.0;
              }
              else
              {
                migrrate(yz,k)(0,migr_start(s,gp)-1)=1.0;
              }
            }
          }
        }
      }    //  end source areas loop
    }  // end growth pattern
  }  // end season

  //  SS_Label_Info_20.2.4 #Copy annual migration rates forward until first year with time-varying migration rates
  if(yz<endyr)
  {
    k=yz+1;
    while(timevary_MG(k,5)==0 && k<=endyr)
    {
      migrrate(k)=migrrate(k-1);  k++;
    }
  }
//  end migration
  }


FUNCTION void get_saveGparm()
  {
  //*********************************************************************
  /*  SS_Label_Function_21 #get_saveGparm */
    gp=0;
    for (gg=1;gg<=gender;gg++)
    for (GPat=1;GPat<=N_GP;GPat++)
    {
      gp++;
      g=g_Start(gp);  //  base platoon
      for (settle=1;settle<=N_settle_timings;settle++)
      {
        g+=N_platoon;
        save_gparm++;
        save_G_parm(save_gparm,1)=save_gparm;
        save_G_parm(save_gparm,2)=y;
        save_G_parm(save_gparm,3)=g;
        save_G_parm(save_gparm,4)=AFIX;
        save_G_parm(save_gparm,5)=AFIX2;
        save_G_parm(save_gparm,6)=value(Lmin(gp));
        save_G_parm(save_gparm,7)=value(Lmax_temp(gp));
        if(do_ageK==1)
        {
          save_G_parm(save_gparm,8)=value(-VBK(gp,nages)*VBK_seas(0));
          save_G_parm(save_gparm,9)=value( -log(L_inf(gp)/(L_inf(gp)-Lmin(gp))) / (-VBK(gp,nages)*VBK_seas(0)) +AFIX+azero_G(g) );
        }
        else
        {
          save_G_parm(save_gparm,8)=value(-VBK(gp,0)*VBK_seas(0));
          save_G_parm(save_gparm,9)=value( -log(L_inf(gp)/(L_inf(gp)-Lmin(gp))) / (-VBK(gp,0)*VBK_seas(0)) +AFIX+azero_G(g) );
        }
        
        save_G_parm(save_gparm,10)=value(L_inf(gp));
        save_G_parm(save_gparm,11)=value(CVLmin(gp));
        save_G_parm(save_gparm,12)=value(CVLmax(gp));
        save_G_parm(save_gparm,13)=natM_amin;
        save_G_parm(save_gparm,14)=natM_amax;
        save_G_parm(save_gparm,15)=value(natM(1,GP3(g),0));
        save_G_parm(save_gparm,16)=value(natM(1,GP3(g),nages));
        if(gg==1)
        {
        for (k=1;k<=6;k++) save_G_parm(save_gparm,16+k)=value(wtlen_p(GPat,k));
        }
        else
        {
        for (k=1;k<=2;k++) save_G_parm(save_gparm,16+k)=value(wtlen_p(GPat,k+6));
        }
        save_gparm_print=save_gparm;
      }
      if(MGparm_doseas>0)
        {
          for (s=1;s<=nseas;s++)
          {
            for (k=1;k<=8;k++)
            {
            save_seas_parm(s,k)=value(wtlen_p(GPat,k)*wtlen_seas(s,GPat,k));
            }
            save_seas_parm(s,9)=value(Lmin(1));
            if(Grow_type<=2 || Grow_type==8) save_seas_parm(s,10)=value(VBK(1,0)*VBK_seas(s));
            if(Grow_type>=3 && Grow_type<=5) save_seas_parm(s,10)=value(VBK(1,nages)*VBK_seas(s));
          }
        }
    }
  }  //  end save_gparm

FUNCTION void Make_Fecundity()
  {
//********************************************************************
//  this Make_Fecundity function does the dot product of the distribution of length-at-age (ALK) with maturity and fecundity vectors
//  to calculate the mean fecundity at each age
 /* SS_Label_31.1 FUNCTION Make_Fecundity */
//  SPAWN-RECR:   here is the make_Fecundity function
    fec.initialize();
    ALK_idx=(spawn_seas-1)*N_subseas+spawn_subseas;
    for (g=1;g<=gmorph;g++)
    if(sx(g)==1 && use_morph(g)>0)
    {
      GPat=GP4(g);
      gg=sx(g);
      switch(Maturity_Option)
      {
        case 4:  //  Maturity_Option=4   read age-fecundity into age-maturity
        {
          fec(g)=Age_Maturity(GPat);
          break;
        }
        case 5:  //  Maturity_Option=5   read age-fecundity from wtatage.ss
        {
          fec(g)=WTage_emp(t,GP3(g),-2);
           break;
        }
        default:
        {
              int ALK_finder=(ALK_idx-1)*gmorph+g;
          for(a=First_Mature_Age;a<=nages;a++)
          {
            tempvec_a(a) = ALK(ALK_idx,g,a)(ALK_range_g_lo(ALK_finder,a),ALK_range_g_hi(ALK_finder,a)) *mat_fec_len(GPat)(ALK_range_g_lo(ALK_finder,a),ALK_range_g_hi(ALK_finder,a));
          }
          fec(g)(First_Mature_Age,nages) = elem_prod(tempvec_a(First_Mature_Age,nages),mat_age(GPat)(First_Mature_Age,nages));  //  reproductive output at age
        }
      }

 /*
      switch(Maturity_Option)
      {
        case 1:  //  Maturity_Option=1  length logistic
        {
//          for(a=0;a<=nages;a++)
//          {
//            fec(g,a) = ALK(ALK_idx,g,a)(ALK_range_g_lo(g,a),ALK_range_g_hi(g,a)) *mat_fec_len(GPat)(ALK_range_g_lo(g,a),ALK_range_g_hi(g,a))*mat_age(GPat,a);  //  reproductive output at age
//          }
//          fec(g) = elem_prod(ALK(ALK_idx,g)*mat_fec_len(GPat),mat_age(GPat));  //  reproductive output at age
          break;
        }
        case 2:  //  Maturity_Option=2  age logistic
        {
          fec(g) = elem_prod(ALK(ALK_idx,g)*mat_fec_len(GPat),mat_age(GPat));  //  reproductive output at age
          break;
        }
        case 3:  //  Maturity_Option=3  read age-maturity
        {
          fec(g) = elem_prod(ALK(ALK_idx,g)*mat_fec_len(GPat),mat_age(GPat));  //  reproductive output at age
          break;
        }
        case 4:  //  Maturity_Option=4   read age-fecundity into age-maturity
        {
          fec(g)=Age_Maturity(GPat);
          break;
        }
        case 5:  //  Maturity_Option=5   read age-fecundity from wtatage.ss
        {
          fec(g)=WTage_emp(t,GP3(g),-2);
           break;
        }
        case 6:  //  Maturity_Option=6   read length-maturity
        {
          fec(g) = elem_prod(ALK(ALK_idx,g)*mat_fec_len(GPat),mat_age(GPat));  //  reproductive output at age
          break;
        }
      }
 */
      if( bigsaver==1 )
      {
      switch(Maturity_Option)
      {
        case 1:  //  Maturity_Option=1  length logistic
        {
          make_mature_numbers(g)=elem_prod(ALK(ALK_idx,g)*mat_len(GPat),mat_age(GPat));  //  mature numbers at age
          make_mature_bio(g)=elem_prod(ALK(ALK_idx,g)*elem_prod(mat_len(GPat),wt_len(s,GP(g))),mat_age(GPat));  //  mature biomass at age

          break;
        }
        case 2:  //  Maturity_Option=2  age logistic
        {
          make_mature_numbers(g)=elem_prod(ALK(ALK_idx,g)*mat_len(GPat),mat_age(GPat));  //  mature numbers at age
          make_mature_bio(g)=elem_prod(ALK(ALK_idx,g)*elem_prod(mat_len(GPat),wt_len(s,GP(g))),mat_age(GPat));  //  mature biomass at age
          break;
        }
        case 3:  //  Maturity_Option=3  read age-maturity
        {
          make_mature_numbers(g)=elem_prod(ALK(ALK_idx,g)*mat_len(GPat),mat_age(GPat));  //  mature numbers at age (Age_Maturity already copied to mat_age)
          make_mature_bio(g)=elem_prod(ALK(ALK_idx,g)*elem_prod(mat_len(GPat),wt_len(s,GP(g))),mat_age(GPat));  //  mature biomass at age
          break;
        }
        case 4:  //  Maturity_Option=4   read age-fecundity, so no age-maturity
        {
          make_mature_numbers(g)=fec(g);  //  not defined
          make_mature_bio(g)=fec(g);   //  not defined
          break;
        }
        case 5:  //  Maturity_Option=5   read age-fecundity from wtatage.ss
        {
          make_mature_numbers(g)=fec(g);  //  not defined
          make_mature_bio(g)=fec(g);   //  not defined
          break;
        }
        case 6:  //  Maturity_Option=6   read length-maturity
        {
          make_mature_numbers(g)=elem_prod(ALK(ALK_idx,g)*mat_len(GPat),mat_age(GPat));  //  mature numbers at age (Length_Maturity already copied to mat_len)
          make_mature_bio(g)=elem_prod(ALK(ALK_idx,g)*elem_prod(mat_len(GPat),wt_len(s,GP(g))),mat_age(GPat));  //  mature biomass at age
          break;
        }
      }
      }

 /*
      if(Maturity_Option<=3)
      {
        fec(g) = ALK(ALK_idx,g)*mat_fec_len;
        if(Maturity_Option==3)
        {fec(g) = elem_prod(fec(g),Age_Maturity(GP4(g)));}
        else
        {fec(g) = elem_prod(fec(g),mat_age);}
      }
      else if(Maturity_Option==4)
      {fec(g)=Age_Maturity(GP4(g));}
      else
      {fec(g)=WTage_emp(t,GP3(g),-2);}
 */
        if(t>=styr) save_sel_fec(t,g,0)= fec(g);   //  save sel_al_3 and save fecundity for output
        if(y==endyr) save_sel_fec(t+nseas,g,0)=fec(g);
    }
  }
