{-# OPTIONS_GHC -XBangPatterns #-}

-----------------------------------------------------------------------------
-- Module      : Math.Statistics
-- Copyright   : (c) 2008 Marshall Beddoe
-- License     : BSD3
--
-- Maintainer  : mbeddoe@<nospam>gmail.com
-- Stability   : experimental
-- Portability : portable
--
-- Description :
--   A collection of commonly used statistical functions.
-----------------------------------------------------------------------------

module Math.Statistics ( -- * Type classes for samples
                         Sample(..)
                       , Wgh
                       -- * Sample parameters 
                       -- ** Variants of mean
                       , harmean
                       , geomean
                       -- ** Variance, standard deviation and moments
                       , stddev
                       , stddevp
                       , pvar
                       , devsq
                       -- ** Skewness and kurtosis
                       , skew
                       , pearsonSkew1
                       , pearsonSkew2
                       , kurt
                       -- ** Median, mode and quantiles
                       , range
                       , median
                       , mode
                       , modes
                       , iqr
                       , quantile
                       , quantileAsc
                       -- ** Other parameters
                       , avgdev
                       -- * Covariance and corelation
                       , covar
                       , covMatrix
                       , pearson
                       , correl
                       -- * Simple regressions
                       , linreg
                       ) where

import Data.List
import Data.Ord (comparing)


----------------------------------------------------------------

-- | Sample. 
class Sample s where
    -- | Mean of sample 
    mean :: Fractional a => s a -> a 
    -- | Unbiased estimate of sample variance. It's different from
    --   second central moment
    var  :: Fractional a => s a -> a 
    -- | Calculate nth moment of sample.
    centralMoment :: (Fractional a, Integral t) => s a -> t -> a 


----------------------------------------------------------------
-- Sample instances. 

instance Sample [] where
    -- Mean 
    mean xs = fst $ foldl' addElement (0,0) xs
        where 
          addElement (!m,!n) x = (m + (x-m)/(n+1), n+1)
    -- Variance 
    var xs = (var' 0 0 0 xs) / (fromIntegral $ length xs - 1)
        where
          var' _ _ s [] = s
          var' m n s (x:xs) = var' nm (n + 1) (s + delta * (x - nm)) xs
              where
                delta = x - m
                nm    = m + delta/(fromIntegral $ n + 1)
    -- Central moment 
    centralMoment xs 1 = 0
    centralMoment xs r = (sum $ map (\x -> (x-m)^r) xs) / (fromIntegral $ length xs)
        where
          m = mean xs

-- | Random sample with weights.
newtype Wgh a = Wgh [(a,a)]

instance Sample Wgh where
    -- mean
    mean (Wgh xs) = (sum . map (uncurry (*)) $ xs) / (sum . map snd $ xs)
    -- Variance
    var xs = centralMoment xs 2
    -- Central moment
    centralMoment _ 1 = 0
    centralMoment (Wgh xs) r = (sum $ map (\(x,w) -> w*(x - m)^r) xs) / (sum $ map snd xs)
        where
          m = mean (Wgh xs)


----------------------------------------------------------------
-- Mean variants 

-- |Harmonic mean
harmean :: (Fractional a) => [a] -> a
harmean xs = fromIntegral (length xs) / (sum $ map (1/) xs)

-- |Geometric mean
geomean :: (Floating a) => [a] -> a
geomean xs = (foldr1 (*) xs)**(1 / fromIntegral (length xs))


----------------------------------------------------------------
-- Variance, standard deviation and moments

-- | Unbiased estimate of standard deviation of sample
stddev :: (Floating a, Sample s) => s a -> a
stddev = sqrt . var

-- |Standard deviation of population
stddevp :: (Floating a, Sample s) => s a -> a
stddevp = sqrt . pvar

-- |Population variance
pvar :: (Fractional a, Sample s) => s a -> a
pvar xs = centralMoment xs 2

-- |Returns the sum of square deviations from their sample mean.
devsq :: Fractional a => [a] -> a
devsq xs = sum $ map (\x -> (x - mean xs)^2) xs


----------------------------------------------------------------
-- Skewness and kurtosis 

-- |Calculate skew
skew :: (Floating a, Sample s) => s a -> a
skew xs = (centralMoment xs 3) / (centralMoment xs 2)**(3/2)

-- |Calculates first Pearson skewness coeffcient.
pearsonSkew1 :: (Ord a, Floating a) => [a] -> a
pearsonSkew1 xs = 3 * (mean xs - mo) / stddev xs
    where
      mo = snd $ head $ modes xs

-- | Calculate second Pearson skewness coeffcient.
pearsonSkew2 :: (Ord a, Floating a) => [a] -> a
pearsonSkew2 xs = 3 * (mean xs - median xs) / stddev xs

-- |Kurtosis
kurt :: (Floating a, Sample s) => s a -> a
kurt xs = (centralMoment xs 4 / (centralMoment xs 2)^2) - 3


----------------------------------------------------------------
-- Median. mode, quantiles 

-- |Median of sample 
median :: (Fractional a, Ord a) => [a] -> a
median x | odd n  = head  $ drop (n `div` 2) x'
         | even n = mean $ take 2 $ drop i x'
                  where i = (length x' `div` 2) - 1
                        x' = sort x
                        n  = length x

-- |Modes returns a sorted list of modes in descending order
modes :: (Ord a) => [a] -> [(Int, a)]
modes xs = sortBy (comparing $ negate.fst) $ map (\x->(length x, head x)) $ (group.sort) xs

-- |Mode returns the mode of the list, otherwise Nothing
mode :: (Ord a) => [a] -> Maybe a
mode xs = case m of
            [] -> Nothing
            otherwise -> Just . snd $ head m
    where m = filter (\(a,b) -> a > 1) (modes xs)


-- | Range of sample. (Maximum - minimum value)
range :: (Num a, Ord a) => [a] -> a
range xs = maximum xs - minimum xs

-- |Interquartile range
iqr :: [a] -> [a]
iqr xs = take (length xs - 2*q) $ drop q xs
    where
      q = ((length xs) + 1) `div` 4


-- |Arbitrary quantile q of an unsorted list.  The quantile /q/ of /N/
-- |data points is the point whose (zero-based) index in the sorted
-- |data set is closest to /q(N-1)/.
quantile :: (Fractional b, Ord b) => Double -> [b] -> b
quantile q = quantileAsc q . sort

-- |As 'quantile' specialized for sorted data
quantileAsc :: (Fractional b, Ord b) => Double -> [b] -> b
quantileAsc _ [] = error "quantile on empty list"
quantileAsc q xs
    | q < 0 || q > 1 = error "quantile out of range"
    | otherwise = xs !! (quantIndex (length xs) q)
    where quantIndex :: Int -> Double -> Int
          quantIndex len q = case round $ q * (fromIntegral len - 1) of
                               idx | idx < 0    -> error "Quantile index too small"
                                   | idx >= len -> error "Quantile index too large"
                                   | otherwise  -> idx

----------------------------------------------------------------
-- Other parameters 

-- | Average deviation. I.e. mean of absolute value of deviation from mean.
avgdev :: (Fractional a) => [a] -> a
avgdev xs = mean $ map (\x -> abs(x - m)) xs
    where
      m = mean xs


----------------------------------------------------------------
-- Covariance and correlation 

-- |Sample Covariance
covar :: (Floating a) => [a] -> [a] -> a
covar xs ys = sum (zipWith (*) (map f1 xs) (map f2 ys)) / (n-1)
    where
      n = fromIntegral $ length $ xs
      m1 = mean xs
      m2 = mean ys
      f1 = \x -> (x - m1)
      f2 = \x -> (x - m2)

-- |Covariance matrix
covMatrix :: (Floating a) => [[a]] -> [[a]]
covMatrix xs =  split' (length xs) cs
    where
      cs = [ covar a b | a <- xs, b <- xs]
      split' n = unfoldr (\y -> if null y then Nothing else Just $ splitAt n y)

-- |Pearson's product-moment correlation coefficient
pearson :: (Floating a) => [a] -> [a] -> a
pearson x y = covar x y / (stddev x * stddev y)

-- |Same as 'pearson'
correl :: (Floating a) => [a] -> [a] -> a
correl = pearson

----------------------------------------------------------------
-- Simple regressions

-- | Least-squares linear regression of /y/ against /x/ for a
--   collection of (/x/, /y/) data, in the form of (/b0/, /b1/, /r/)
--   where the regression is /y/ = /b0/ + /b1/ * /x/ with Pearson
--   coefficient /r/
linreg :: (Floating b) => [(b, b)] -> (b, b, b)
linreg xys = let !xs  = map fst xys
                 !ys  = map snd xys
                 !n   = fromIntegral $ length xys
                 !sX  = sum xs
                 !sY  = sum ys
                 !sXX = sum $ map (^ 2) xs
                 !sXY = sum $ map (uncurry (*)) xys
                 !sYY = sum $ map (^ 2) ys
                 !alpha = (sY - beta * sX) / n
                 !beta  = (n * sXY - sX * sY) / (n * sXX - sX * sX)
                 !r     = (n * sXY - sX * sY) / (sqrt $ (n * sXX - sX^2) * (n * sYY - sY ^ 2))
             in (alpha, beta, r)
