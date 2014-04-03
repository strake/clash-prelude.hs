{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeFamilies        #-}

module CLaSH.Signal.Explicit
  ( -- * Explicitly clocked synchronous signal
    CSignal
    -- * Clock domain crossing
  , Clock (..)
  , veryUnsafeSynchronizer
  , fromImplicit
  , fromExplicit
  -- * Basic circuit functions
  , csignal
  , cregister
  , CPack (..)
  -- * Simulation functions
  , csimulate
  , csimulateP
    -- * List \<-\> CSignal conversion
  , csample
  , csampleN
  , cfromList
  )
where

import Data.Coerce
import Control.Applicative        (Applicative (..), (<$>), liftA2)
import GHC.TypeLits               (Nat)

import CLaSH.Bit                  (Bit)
import CLaSH.Promoted.Nat         (snatToInteger)
import CLaSH.Sized.Fixed          (Fixed)
import CLaSH.Sized.Signed         (Signed)
import CLaSH.Sized.Unsigned       (Unsigned)
import CLaSH.Sized.Vector         (Vec(..), vmap, vhead, vtail)

import CLaSH.Signal.Implicit
import CLaSH.Signal.Types

{-# NOINLINE cregister  #-}

{-# NOINLINE veryUnsafeSynchronizer #-}
{-# NOINLINE fromImplicit           #-}
{-# NOINLINE fromExplicit           #-}

-- | Create a 'CSignal' from a list
--
-- Every element in the list will correspond to a value of the signal for one
-- clock cycle.
--
-- NB: Simulation only!
--
-- >>> csampleN 2 (cfromList [1,2,3,4,5])
-- [1,2]
cfromList :: [a] -> CSignal t a
cfromList = coerce . fromList

-- | Get an infinite list of samples from a 'CSignal'
--
-- The elements in the list correspond to the values of the 'CSignal' at
-- consecutive clock cycles
--
-- > csample s == [s0, s1, s2, s3, ...
csample :: CSignal t a -> [a]
csample = sample . coerce

-- | Get a list of @n@ samples from a 'CSignal'
--
-- The elements in the list correspond to the values of the 'CSignal' at
-- consecutive clock cycles
--
-- > csampleN 3 s == [s0, s1, s2]
csampleN :: Int -> CSignal t a -> [a]
csampleN n = sampleN n . coerce

-- | 'cregister' @i s@ delays the values in 'CSignal' @s@ for one cycle, and sets
-- the value at time 0 to @i@
--
-- > clk100 = Clock d100
--
-- >>> csampleN 3 (cregister d100 8 (fromList [1,2,3,4]))
-- [8,1,2]
cregister :: Clock clk -> a -> CSignal clk a -> CSignal clk a
cregister _ i s = coerce (register i (coerce s))

-- | Simulate a (@'CSignal' clk1 a -> 'Signal' clk2 b@) function given a list of
-- samples of type @a@
--
-- >>> simulate (register 8) [1, 2, 3, ...
-- [8, 1, 2, 3, ...
csimulate :: (CSignal clk1 a -> CSignal clk2 b) -> [a] -> [b]
csimulate f = csample . f . cfromList

-- | Conversion between a 'Signal' of a product type (e.g. a tuple) and a
-- product type of 'Signal's
class CPack a where
  type CSignalP (clk :: Nat) a
  type CSignalP clk a = CSignal clk a
  -- | > pack :: (Signal a, Signal b) -> Signal (a,b)
  -- However:
  --
  -- > pack :: Signal Bit -> Signal Bit
  cpack   :: Clock clk -> CSignalP clk a -> CSignal clk a
  -- | > unpack :: Signal (a,b) -> (Signal a, Signal b)
  -- However:
  --
  -- > unpack :: Signal Bit -> Signal Bit
  cunpack :: Clock clk -> CSignal clk a -> CSignalP clk a

-- | Simulate a (@'CSignalP' clk1 a -> 'CSignalP' clk2 b@) function given a list
-- of samples of type @a@
--
-- > clk100 = Clock d100
--
-- >>> csimulateP clk100 clk100 (cunpack clk100 . cregister clk100 (8,8) . cpack clk100) [(1,1), (2,2), (3,3), ...
-- [(8,8), (1,1), (2,2), (3,3), ...
csimulateP :: (CPack a, CPack b)
           => Clock clk1 -- ^ 'Clock' of the incoming signal
           -> Clock clk2 -- ^ 'Clock' of the outgoing signal
           -> (CSignalP clk1 a -> CSignalP clk2 b) -- ^ Function to simulate
           -> [a] -> [b]
csimulateP clk1 clk2 f = csimulate (cpack clk2 . f . cunpack clk1)

instance CPack Bit where
  cpack   _ = id
  cunpack _ = id

instance CPack (Signed n) where
  cpack   _ = id
  cunpack _ = id

instance CPack (Unsigned n) where
  cpack   _ = id
  cunpack _ = id

instance CPack (Fixed frac rep size) where
  cpack   _ = id
  cunpack _ = id

instance CPack Bool where
  cpack   _ = id
  cunpack _ = id

instance CPack Integer where
  cpack   _ = id
  cunpack _ = id

instance CPack Int where
  cpack   _ = id
  cunpack _ = id

instance CPack Float where
  cpack   _ = id
  cunpack _ = id

instance CPack Double where
  cpack   _ = id
  cunpack _ = id

instance CPack () where
  cpack   _ = id
  cunpack _ = id

instance CPack (a,b) where
  type CSignalP t (a,b) = (CSignal t a, CSignal t b)
  cpack _       = uncurry (liftA2 (,))
  cunpack _ tup = (fmap fst tup, fmap snd tup)

instance CPack (a,b,c) where
  type CSignalP t (a,b,c) = (CSignal t a, CSignal t b, CSignal t c)
  cpack   _ (a,b,c) = (,,) <$> a <*> b <*> c
  cunpack _ tup     = (fmap (\(x,_,_) -> x) tup
                      ,fmap (\(_,x,_) -> x) tup
                      ,fmap (\(_,_,x) -> x) tup
                      )

instance CPack (a,b,c,d) where
  type CSignalP t (a,b,c,d) = (CSignal t a, CSignal t b, CSignal t c, CSignal t d)
  cpack   _ (a,b,c,d) = (,,,) <$> a <*> b <*> c <*> d
  cunpack _ tup       = (fmap (\(x,_,_,_) -> x) tup
                        ,fmap (\(_,x,_,_) -> x) tup
                        ,fmap (\(_,_,x,_) -> x) tup
                        ,fmap (\(_,_,_,x) -> x) tup
                        )

instance CPack (a,b,c,d,e) where
  type CSignalP t (a,b,c,d,e) = (CSignal t a, CSignal t b, CSignal t c, CSignal t d, CSignal t e)
  cpack _ (a,b,c,d,e) = (,,,,) <$> a <*> b <*> c <*> d <*> e
  cunpack _ tup       = (fmap (\(x,_,_,_,_) -> x) tup
                        ,fmap (\(_,x,_,_,_) -> x) tup
                        ,fmap (\(_,_,x,_,_) -> x) tup
                        ,fmap (\(_,_,_,x,_) -> x) tup
                        ,fmap (\(_,_,_,_,x) -> x) tup
                        )

instance CPack (a,b,c,d,e,f) where
  type CSignalP t (a,b,c,d,e,f) = (CSignal t a, CSignal t b, CSignal t c, CSignal t d, CSignal t e, CSignal t f)
  cpack   _ (a,b,c,d,e,f) = (,,,,,) <$> a <*> b <*> c <*> d <*> e <*> f
  cunpack _ tup           = (fmap (\(x,_,_,_,_,_) -> x) tup
                            ,fmap (\(_,x,_,_,_,_) -> x) tup
                            ,fmap (\(_,_,x,_,_,_) -> x) tup
                            ,fmap (\(_,_,_,x,_,_) -> x) tup
                            ,fmap (\(_,_,_,_,x,_) -> x) tup
                            ,fmap (\(_,_,_,_,_,x) -> x) tup
                            )

instance CPack (a,b,c,d,e,f,g) where
  type CSignalP t (a,b,c,d,e,f,g) = (CSignal t a, CSignal t b, CSignal t c, CSignal t d, CSignal t e, CSignal t f, CSignal t g)
  cpack   _ (a,b,c,d,e,f,g) = (,,,,,,) <$> a <*> b <*> c <*> d <*> e <*> f <*> g
  cunpack _ tup             = (fmap (\(x,_,_,_,_,_,_) -> x) tup
                              ,fmap (\(_,x,_,_,_,_,_) -> x) tup
                              ,fmap (\(_,_,x,_,_,_,_) -> x) tup
                              ,fmap (\(_,_,_,x,_,_,_) -> x) tup
                              ,fmap (\(_,_,_,_,x,_,_) -> x) tup
                              ,fmap (\(_,_,_,_,_,x,_) -> x) tup
                              ,fmap (\(_,_,_,_,_,_,x) -> x) tup
                              )

instance CPack (a,b,c,d,e,f,g,h) where
  type CSignalP t (a,b,c,d,e,f,g,h) = (CSignal t a, CSignal t b, CSignal t c, CSignal t d, CSignal t e, CSignal t f, CSignal t g, CSignal t h)
  cpack   _ (a,b,c,d,e,f,g,h) = (,,,,,,,) <$> a <*> b <*> c <*> d <*> e <*> f <*> g <*> h
  cunpack _ tup               = (fmap (\(x,_,_,_,_,_,_,_) -> x) tup
                                ,fmap (\(_,x,_,_,_,_,_,_) -> x) tup
                                ,fmap (\(_,_,x,_,_,_,_,_) -> x) tup
                                ,fmap (\(_,_,_,x,_,_,_,_) -> x) tup
                                ,fmap (\(_,_,_,_,x,_,_,_) -> x) tup
                                ,fmap (\(_,_,_,_,_,x,_,_) -> x) tup
                                ,fmap (\(_,_,_,_,_,_,x,_) -> x) tup
                                ,fmap (\(_,_,_,_,_,_,_,x) -> x) tup
                                )

instance CPack (Vec n a) where
  type CSignalP t (Vec n a) = Vec n (CSignal t a)
  cpack clk vs = mkCSignal (vmap (shead . coerce) vs) (cpack clk (vmap cstail vs))
  cunpack _      (CSignal (Nil :- _))      = Nil
  cunpack clk vs@(CSignal ((_ :> _) :- _)) = fmap vhead vs :> cunpack clk (fmap vtail vs)

-- | Synchronisation function that is basically a represented by a (bundle of)
-- wire(s) in hardware. This function should only be used as part of a proper
-- synchronisation component, such as a dual flip-flop synchronizer, or a FIFO
-- with an asynchronous memory element:
--
-- > dualFlipFlop :: Clock clk1 -> Clock clk2
-- >              -> CSignal clk1 Bit -> CSignal clk2 Bit
-- > dualFlipFlop clk1 clk2 = cregister clk2 L . cregister clk2 L . veryUnsafeSynchronizer clk1 clk2
--
-- Currently, this 'veryUnsafeSynchronizer' function oversimplifies oversampling
-- and compression: oversampling and compression rates are calculated using
-- integer division (round towards 0).
--
-- So, given:
--
-- > clk7 = Clock d7
-- > clk6 = Clock d6
-- > clk2 = Clock d4
--
-- Oversampling from @clk6@ to @clk2@:
--
-- >>> csample (veryUnsafeSynchronizer clk6 clk2 (cfromList [1,2,3,4,5,6,7,8,9,10]))
-- [1,1,1,2,2,2, 3,3,3,4,4,4, 5,5,5,6,6,...
--
-- Gives the same result as \"oversampling\" from @clk7@ to @clk2@:
--
-- >>> csample (veryUnsafeSynchronizer clk7 clk2 (cfromList [1,2,3,4,5,6,7,8,9,10]))
-- [1,1,1,2,2,2, 3,3,3,4,4,4, 5,5,5,6,6,...
--
-- That is, 2 samples at @clk7@ are \"oversampled\" to only 6 samples at @clk2@;
-- meaning that there is actually a slight undersampling! A \"better\", but
-- currently unimplemented, synchronisation function would give the following
-- result:
--
-- >>> csample (veryUnsafeSynchronizer clk7 clk2 (cfromList [1,2,3,4,5,6,7,8,9,10]))
-- [1,1,1,2,2,2,2, 3,3,3,4,4,4,4, 5,5,5,6,6,...
--
-- Where 2 samples at @clk7@ are properly oversampled to 7 samples at @clk2@.
veryUnsafeSynchronizer :: Clock clk1 -- ^ 'Clock' of the incoming signal
                       -> Clock clk2 -- ^ 'Clock' of the outgoing signal
                       -> CSignal clk1 a
                       -> CSignal clk2 a
veryUnsafeSynchronizer (Clock clk1) (Clock clk2) s = s'
  where
    t1    = snatToInteger clk1
    t2    = snatToInteger clk2
    s' | t1 < t2   = compress   (t2 `div` t1) s -- Integer devision is erroneous
       | t1 > t2   = oversample (t1 `div` t2) s -- Integer devision is erroneous
       | otherwise = same s

same :: CSignal clk1 a -> CSignal clk2 a
same (CSignal s) = CSignal s

-- Probably needs more parametrization
oversample :: Integer -> CSignal clk1 a -> CSignal clk2 a
oversample i (CSignal (s :- ss)) = (prefix (replicate (fromInteger i) s) (oversample i (CSignal ss)))
  where
    prefix []     s' = s'
    prefix (x:xs) s' = mkCSignal x (prefix xs s')

-- Probably needs more parametrization
compress :: Integer -> CSignal clk1 a -> CSignal clk2 a
compress i (CSignal x) = CSignal (compress' i x)
  where
    compress' 1 (s :- ss) = s :- compress' i ss
    compress' n (_ :- ss) = compress' (n-1) ss

-- | Implicitly clocked signals have a clock with period 1000
fromImplicit :: Signal a -> CSignal 1000 a
fromImplicit s = CSignal s

-- | Implicitly clocked signals have a clock with period 1000
fromExplicit :: CSignal 1000 a -> Signal a
fromExplicit (CSignal s) = s