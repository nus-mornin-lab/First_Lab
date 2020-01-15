-- Extract dataframe for first lab paper
-- 20 Sep 2017

-- Author: Du Hao

DROP MATERIALIZED VIEW IF EXISTS first_lab CASCADE;
CREATE MATERIALIZED VIEW first_lab as

WITH pvt AS (
  SELECT ie.subject_id, ie.hadm_id, ie.outtime, ie.icustay_id, le.charttime, ad.deathtime, ie.los
  , os.oasis
  --, le.valueuom AS valueuom 
  , RANK() OVER (PARTITION BY ie.subject_id ORDER BY ie.intime) AS icustay_id_order
  , EXTRACT('epoch' from ie.intime - p.dob) / 60.0 / 60.0 / 24.0 /365.242 as first_admit_age
  , ie.first_careunit, ie.last_careunit
  , p.gender
  , CASE when ve.mechvent = 1.0 THEN 1 ELSE 0 END AS mechvent
  , va.vasonum
  , CASE when ad.deathtime between ie.intime and ie.outtime THEN 1 ELSE 0 END AS mort_icu
  , CASE when ad.deathtime between ad.admittime and ad.dischtime THEN 1 ELSE 0 END AS mort_hosp
  -- here we assign labels to ITEMIDs
  -- this also fuses together multiple ITEMIDs containing the same data
  , CASE
        when le.itemid = 50868 then 'ANION GAP'
        when le.itemid = 50862 then 'ALBUMIN'
        when le.itemid = 50882 then 'BICARBONATE'
        when le.itemid = 50885 then 'BILIRUBIN'
        when le.itemid = 50912 then 'CREATININE'
        when le.itemid = 50806 then 'CHLORIDE'
        when le.itemid = 50902 then 'CHLORIDE'
        when itemid = 50809 then 'GLUCOSE'
        when itemid = 50931 then 'GLUCOSE'
        when itemid = 50810 then 'HEMATOCRIT'
        when itemid = 51221 then 'HEMATOCRIT'
        when itemid = 50811 then 'HEMOGLOBIN'
        when itemid = 51222 then 'HEMOGLOBIN'
        when itemid = 50813 then 'LACTATE'
        when itemid = 50960 then 'MAGNESIUM'
        when itemid = 50970 then 'PHOSPHATE'
        when itemid = 51265 then 'PLATELET'
        when itemid = 50822 then 'POTASSIUM'
        when itemid = 50971 then 'POTASSIUM'
        when itemid = 51275 then 'PTT'
        when itemid = 51237 then 'INR'
        when itemid = 51274 then 'PT'
        when itemid = 50824 then 'SODIUM'
        when itemid = 50983 then 'SODIUM'
        when itemid = 51006 then 'BUN'
        when itemid = 51300 then 'WBC'
        when itemid = 51301 then 'WBC'
        -- Calcium
        when itemid = 50893 then 'CALCIUM'
        -- Free calcium
        when itemid = 50808 then 'FREECALCIUM'
      ELSE null
      END AS label
  , -- add in some sanity checks on the values
    -- the where clause below requires all valuenum to be > 0,
    -- so these are only upper limit checks
    CASE
      when le.itemid = 50862 and le.valuenum >    10 then null -- g/dL 'ALBUMIN'
      when le.itemid = 50868 and le.valuenum > 10000 then null -- mEq/L 'ANION GAP'
      when le.itemid = 50882 and le.valuenum > 10000 then null -- mEq/L 'BICARBONATE'
      when le.itemid = 50885 and le.valuenum >   150 then null -- mg/dL 'BILIRUBIN'
      when le.itemid = 50806 and le.valuenum > 10000 then null -- mEq/L 'CHLORIDE'
      when le.itemid = 50902 and le.valuenum > 10000 then null -- mEq/L 'CHLORIDE'
      when le.itemid = 50912 and le.valuenum >   150 then null -- mg/dL 'CREATININE'
      when le.itemid = 50809 and le.valuenum > 10000 then null -- mg/dL 'GLUCOSE'
      when le.itemid = 50931 and le.valuenum > 10000 then null -- mg/dL 'GLUCOSE'
      when le.itemid = 50810 and le.valuenum >   100 then null -- % 'HEMATOCRIT'
      when le.itemid = 51221 and le.valuenum >   100 then null -- % 'HEMATOCRIT'
      when le.itemid = 50811 and le.valuenum >    50 then null -- g/dL 'HEMOGLOBIN'
      when le.itemid = 51222 and le.valuenum >    50 then null -- g/dL 'HEMOGLOBIN'
      when le.itemid = 50813 and le.valuenum >    50 then null -- mmol/L 'LACTATE'
      when le.itemid = 50960 and le.valuenum >    60 then null -- mmol/L 'MAGNESIUM'
      when le.itemid = 50970 and le.valuenum >    60 then null -- mg/dL 'PHOSPHATE'
      when le.itemid = 51265 and le.valuenum > 10000 then null -- K/uL 'PLATELET'
      when le.itemid = 50822 and le.valuenum >    30 then null -- mEq/L 'POTASSIUM'
      when le.itemid = 50971 and le.valuenum >    30 then null -- mEq/L 'POTASSIUM'
      when le.itemid = 51275 and le.valuenum >   150 then null -- sec 'PTT'
      when le.itemid = 51237 and le.valuenum >    50 then null -- 'INR'
      when le.itemid = 51274 and le.valuenum >   150 then null -- sec 'PT'
      when le.itemid = 50824 and le.valuenum >   200 then null -- mEq/L == mmol/L 'SODIUM'
      when le.itemid = 50983 and le.valuenum >   200 then null -- mEq/L == mmol/L 'SODIUM'
      when le.itemid = 51006 and le.valuenum >   300 then null -- 'BUN'
      when le.itemid = 51300 and le.valuenum >  1000 then null -- 'WBC'
      when le.itemid = 51301 and le.valuenum >  1000 then null -- 'WBC'
      -- Calcium
      when le.itemid = 50893 and le.valuenum > 300 then null
      -- Free Calcium
      when le.itemid = 50808 and le.valuenum > 500 then null
    ELSE le.valuenum
    END AS valuenum
  FROM mimiciii.icustays ie

  LEFT JOIN  mimiciii.labevents le
    ON le.subject_id = ie.subject_id
    AND le.hadm_id = ie.hadm_id
    AND le.charttime between (ie.intime - interval '24' hour)
    AND (ie.intime + interval '24' hour)
    AND le.itemid IN
    (
      -- comment is: LABEL | CATEGORY | FLUID | NUMBER OF ROWS IN LABEVENTS
      50868, -- ANION GAP | CHEMISTRY | BLOOD | 769895
      50862, -- ALBUMIN | CHEMISTRY | BLOOD | 146697
      50882, -- BICARBONATE | CHEMISTRY | BLOOD | 780733
      50885, -- BILIRUBIN, TOTAL | CHEMISTRY | BLOOD | 238277
      50912, -- CREATININE | CHEMISTRY | BLOOD | 797476
      50902, -- CHLORIDE | CHEMISTRY | BLOOD | 795568
      50806, -- CHLORIDE, WHOLE BLOOD | BLOOD GAS | BLOOD | 48187
      50931, -- GLUCOSE | CHEMISTRY | BLOOD | 748981
      50809, -- GLUCOSE | BLOOD GAS | BLOOD | 196734
      51221, -- HEMATOCRIT | HEMATOLOGY | BLOOD | 881846
      50810, -- HEMATOCRIT, CALCULATED | BLOOD GAS | BLOOD | 89715
      51222, -- HEMOGLOBIN | HEMATOLOGY | BLOOD | 752523
      50811, -- HEMOGLOBIN | BLOOD GAS | BLOOD | 89712
      50813, -- LACTATE | BLOOD GAS | BLOOD | 187124
      50960, -- MAGNESIUM | CHEMISTRY | BLOOD | 664191
      50970, -- PHOSPHATE | CHEMISTRY | BLOOD | 590524
      51265, -- PLATELET COUNT | HEMATOLOGY | BLOOD | 778444
      50971, -- POTASSIUM | CHEMISTRY | BLOOD | 845825
      50822, -- POTASSIUM, WHOLE BLOOD | BLOOD GAS | BLOOD | 192946
      51275, -- PTT | HEMATOLOGY | BLOOD | 474937
      51237, -- INR(PT) | HEMATOLOGY | BLOOD | 471183
      51274, -- PT | HEMATOLOGY | BLOOD | 469090
      50983, -- SODIUM | CHEMISTRY | BLOOD | 808489
      50824, -- SODIUM, WHOLE BLOOD | BLOOD GAS | BLOOD | 71503
      51006, -- UREA NITROGEN | CHEMISTRY | BLOOD | 791925
      51301, -- WHITE BLOOD CELLS | HEMATOLOGY | BLOOD | 753301
      51300,  -- WBC COUNT | HEMATOLOGY | BLOOD | 2371
      -- calcium total
      50893, -- CALCIUM TOTAL | NA | NA | NA
      -- Free calcium
      50808  --FREE CALCIUM | NA | NA | NA
    )
    AND le.valuenum IS NOT null
    AND le.valuenum > 0 -- lab values cannot be 0 and cannot be negative

    LEFT JOIN  mimiciii.admissions ad
    ON ie.subject_id = ad.subject_id
    AND ie.hadm_id = ad.hadm_id

    LEFT JOIN public.oasis os
    ON ie.subject_id = os.subject_id
    AND ie.hadm_id = os.hadm_id

    LEFT JOIN public.ventsettings ve
    ON ie.icustay_id = ve.icustay_id

    LEFT JOIN public.VASOPRESSORDURATIONS va 
    ON ie.icustay_id = va.icustay_id

    LEFT JOIN mimiciii.patients p
    ON ie.subject_id = p.subject_id
    WHERE ROUND((cast(ad.admittime as date) - cast(p.dob as date)) / 365.242, 2) > 15
    -- WHERE ie.subject_id < 10000
) 

SELECT pvt.subject_id, pvt.hadm_id, pvt.icustay_id, pvt.mort_icu, pvt.mort_hosp
  -- , max(r.hadm_id) as HADM_ID
  -- , max(r.icustay_id) as ICUSTAY_ID
  , max(pvt.mechvent) as Mechvent
  , max(pvt.vasonum) as Vasopressor
  , max(pvt.gender) as Gender
  , max(pvt.first_careunit) as First_careunit
  , max(pvt.last_careunit) as Last_careunit
  , max(pvt.oasis) as OASIS
  , max(pvt.los) as LOS
  , max(pvt.first_admit_age) as FIRST_ADMIT_AGE
  , max(pvt.charttime) as CHARTTIME
  , max(case when label = 'ANION GAP' then valuenum else null end) as ANIONGAP_max
  , min(case when label = 'ANION GAP' then valuenum else null end) as ANIONGAP_min
  
  , max(case when label = 'ALBUMIN' then valuenum else null end) as ALBUMIN_max
  , min(case when label = 'ALBUMIN' then valuenum else null end) as ALBUMIN_min
  
  , max(case when label = 'BICARBONATE' then valuenum else null end) as BICARBONATE_max
  , min(case when label = 'BICARBONATE' then valuenum else null end) as BICARBONATE_min
  
  , max(case when label = 'BILIRUBIN' then valuenum else null end) as BILIRUBIN_max
  , min(case when label = 'BILIRUBIN' then valuenum else null end) as BILIRUBIN_min
  
  , max(case when label = 'CREATININE' then valuenum else null end) as CREATININE_max
  , min(case when label = 'CREATININE' then valuenum else null end) as CREATININE_min
  
  , max(case when label = 'CHLORIDE' then valuenum else null end) as CHLORIDE_max
  , min(case when label = 'CHLORIDE' then valuenum else null end) as CHLORIDE_min
  
  , max(case when label = 'GLUCOSE' then valuenum else null end) as GLUCOSE_max
  , min(case when label = 'GLUCOSE' then valuenum else null end) as GLUCOSE_min
  --, max(case when label = 'GLUCOSE' then valueuom else null end) as GLUCOSE_uom
  
  , max(case when label = 'HEMATOCRIT' then valuenum else null end) as HEMATOCRIT_max
  , min(case when label = 'HEMATOCRIT' then valuenum else null end) as HEMATOCRIT_min
  
  , max(case when label = 'HEMOGLOBIN' then valuenum else null end) as HEMOGLOBIN_max
  , min(case when label = 'HEMOGLOBIN' then valuenum else null end) as HEMOGLOBIN_min
  
  , max(case when label = 'LACTATE' then valuenum else null end) as LACTATE_max
  , min(case when label = 'LACTATE' then valuenum else null end) as LACTATE_min
  
  , max(case when label = 'MAGNESIUM' then valuenum else null end) as MAGNESIUM_max
  , min(case when label = 'MAGNESIUM' then valuenum else null end) as MAGNESIUM_min
  
  , max(case when label = 'PHOSPHATE' then valuenum else null end) as PHOSPHATE_max
  , min(case when label = 'PHOSPHATE' then valuenum else null end) as PHOSPHATE_min
  
  , max(case when label = 'PLATELET' then valuenum else null end) as PLATELET_max
  , min(case when label = 'PLATELET' then valuenum else null end) as PLATELET_min
  --, max(case when label = 'PLATELET' then valueuom else null end) as PLATELET_uom
  
  , max(case when label = 'POTASSIUM' then valuenum else null end) as POTASSIUM_max
  , min(case when label = 'POTASSIUM' then valuenum else null end) as POTASSIUM_min
  
  , max(case when label = 'PTT' then valuenum else null end) as PTT_max
  , min(case when label = 'PTT' then valuenum else null end) as PTT_min
  
  , max(case when label = 'INR' then valuenum else null end) as INR_max
  , min(case when label = 'INR' then valuenum else null end) as INR_min
  
  , max(case when label = 'PT' then valuenum else null end) as PT_max
  , min(case when label = 'PT' then valuenum else null end) as PT_min
  
  , max(case when label = 'SODIUM' then valuenum else null end) as SODIUM_max
  , min(case when label = 'SODIUM' then valuenum else null end) as SODIUM_min
  
  , max(case when label = 'BUN' then valuenum else null end) as BUN_max
  , min(case when label = 'BUN' then valuenum else null end) as BUN_min
  
  , max(case when label = 'WBC' then valuenum else null end) as WBC_max
  , min(case when label = 'WBC' then valuenum else null end) as WBC_min
  -- Calcium
  , max(case when label = 'CALCIUM' then valuenum else null end) as CALCIUM_max
  , min(case when label = 'CALCIUM' then valuenum else null end) as CALCIUM_min
  
  , max(case when label = 'FREECALCIUM' then valuenum else null end) as FREECALCIUM_max
  , min(case when label = 'FREECALCIUM' then valuenum else null end) as FREECALCIUM_min
FROM pvt
-- WHERE r.drank = 1
WHERE pvt.icustay_id_order < 2
GROUP BY pvt.subject_id, pvt.hadm_id, pvt.icustay_id, pvt.mort_icu, pvt.mort_hosp
ORDER BY pvt.subject_id, pvt.hadm_id, pvt.icustay_id, pvt.mort_icu, pvt.mort_hosp;